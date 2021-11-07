// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.7.0 <0.9.0;
import "../KYC/PayToken.sol";
import "../KYC/Governance.sol";

contract KYCProcess
{
    PayToken public payments;
    Governance public governance;
    address public MSP;
    uint public corePrice;
    uint public updatePrice;
    
    uint private nodeIDCounter;
    
    //Can add 10000 clients or KYC process a day for 1E70 years before running out of IDs.
    mapping (uint => Client) private clients;
    mapping (uint => KYCNode) private KYCNodes;
    mapping (uint => address[]) private participants;
    mapping (uint => address[]) private subscribers;
    mapping (uint => bytes32[]) private documentHash;
    
    enum NodeStatus{ Core, Update, Merge }
    
    struct KYCNode
    {
        uint nodeID;
        bool approved;
        NodeStatus status;
        uint update;
        uint updateOf;
        bool allowMerge;
        uint minParticipantsForMerge;
        uint maxParticipantsForMerge;
        bool merged;
        uint prevID;
        uint nextID;
    }
    
    struct Client
    {
        uint id;
        bool created;
        uint KYCNodeID;
        uint KYCProcesses;
        uint updates;
    }
    
    modifier MSP_CHECK {
        require(msg.sender == MSP, 
          "Must be MSP to use this function");
        _;
    }
    
    modifier FI_CHECK {
        require(governance.checkFI(msg.sender), 
          "Must be registered FI to use this function");
        _;
    }
    
    event RequestDocuments(address indexed _from, address indexed _to, uint _nodeID, bytes32 docHash);
    
    constructor()
    {
        MSP = msg.sender;
        payments = new PayToken(msg.sender);
        governance = new Governance(msg.sender);
        nodeIDCounter = 1;
        corePrice = 10000000;
        updatePrice = 5000000;
    }
    
    function getID() private 
        returns (uint)
    {
        uint retval = nodeIDCounter;
        nodeIDCounter += 1;
        return retval;
    }
    
    //Give customer ID
    function clientExists(uint id) FI_CHECK public
        view returns (bool)
    {
        return clients[id].created;
    }
    
    //Give KYC node ID
    function nodeExists(uint id) private 
        view returns (bool)
    {
        return KYCNodes[id].nodeID != 0;
    }
    
    //give node id
    //give address of FI to check if they participate or subscribe
    function isParticipant(uint nid, address addr) public
        view returns (bool)
    {
        require(nodeExists(nid));
        bool retval = false;
        address[] memory p = participants[nid];
        for (uint i = 0; i < p.length; i+=1)
        {
            if (p[i] == addr)
            {
                retval = true;
            }
        }
        return retval;
    }
    
    function isSubscriber(uint nid, address addr) public
        view returns (bool)
    {
        require(nodeExists(nid));
        bool retval = false;
        address[] memory s = subscribers[nid];
        for (uint i = 0; i < s.length; i+=1)
        {
            if (s[i] == addr)
            {
                retval = true;
            }
        }
        return retval;
    }
    
    function addClient(uint cid) FI_CHECK public
    {
        require(!clientExists(cid));
        clients[cid] = Client(cid,true,0,0,0);
    }
    
    //bytes32 example: 0x0000000000000000000000000000000000000000000000000000006d6168616d
    //id example: any CVR 
    function addCoreKYCDocuments(uint cid, bytes32 hash, bool approved,
        bool allowMerge, uint minParticipantsForMerge, uint maxParticipantsForMerge) FI_CHECK public
    {
        if (!clientExists(cid))
        {
            addClient(cid);
        }
        
        uint newNodeID = getID();
        participants[newNodeID].push(msg.sender);
        documentHash[newNodeID].push(hash);
        //first KYC
        if (clients[cid].KYCNodeID == 0) 
        {
            KYCNodes[newNodeID] = KYCNode(newNodeID,approved,NodeStatus.Core,0,0,
                                      allowMerge,minParticipantsForMerge,maxParticipantsForMerge,
                                      false,0,0);
            clients[cid].KYCNodeID = newNodeID;
        }
        //not first but new last
        else
        {
            uint lastID = findLastNode(cid);
            KYCNodes[lastID].nextID = newNodeID;
            KYCNodes[newNodeID] = KYCNode(newNodeID,approved,NodeStatus.Core,0,0,
                                      allowMerge,minParticipantsForMerge,maxParticipantsForMerge,
                                      false,lastID,0);
        }
        clients[cid].KYCProcesses += 1;
    }
    
    function updateKYCDocuments(uint cid, uint nid, bytes32 hash, bool approved,
        bool allowMerge, uint minParticipantsForMerge, uint maxParticipantsForMerge) FI_CHECK public
    {
        require(clientExists(cid), "Client does not exist");
        require(nodeExists(nid), "Process does not exist");
        require(!KYCNodes[nid].merged, "Node cannot be merged");
        require(isParticipant(nid,msg.sender) || 
                isSubscriber(nid,msg.sender))
        uint newNodeID = getID();
        participants[newNodeID].push(msg.sender);
        documentHash[newNodeID].push(hash);
        
        uint lastID = findLastNode(cid);
        KYCNodes[lastID].nextID = newNodeID;
        uint updates = KYCNodes[nid].update;
        KYCNodes[newNodeID] = KYCNode(newNodeID,approved,NodeStatus.Update,updates+1,nid,
                                      allowMerge,minParticipantsForMerge,maxParticipantsForMerge,
                                      false,lastID,0);
        clients[cid].KYCProcesses += 1;
        uint old_highest_update = clients[cid].updates;
        if (old_highest_update < updates + 1)
        {
            clients[cid].updates = updates + 1;
        }
    }
    
    function addMergeKYCProcess(uint cid, uint[] memory nids, bytes32 hash, bool approved) FI_CHECK public
    {
        updateMergeKYCProcess(cid,0,nids,hash,approved);
    }
    
    function subscribeKYCProcess(uint nid) FI_CHECK public
    {
        require(nodeExists(nid), "Process does not exist does not exist");
        require(!isSubscriber(nid,msg.sender), "Already subscribed");
        require(!isParticipant(nid,msg.sender), "Already participant");
        require(!KYCNodes[nid].merged, "Cannot subscribe to merged");
        uint[] memory priceList = priceKYCProcess(nid,msg.sender);
        uint nodeID = nid;
        for (uint i = priceList.length; i > 0; i-=1)
        {
            uint price = priceList[i-1];
            uint n = subscribers[nodeID].length + participants[nodeID].length;
            uint amount = price/n;
            for (uint j = 0; j < subscribers[nodeID].length; j+=1)
            {
                payments.transferTokens(msg.sender,subscribers[nodeID][j],amount);
            }
            for (uint j = 0; j < participants[nodeID].length; j+=1)
            {
                payments.transferTokens(msg.sender,participants[nodeID][j],amount);
                emit RequestDocuments(participants[nodeID][j],msg.sender,nodeID,documentHash[nodeID][j]);
            }
            if (!isSubscriber(nodeID,msg.sender) && !isParticipant(nodeID,msg.sender))
            {
                subscribers[nodeID].push(msg.sender);
            }
            nodeID = KYCNodes[nodeID].updateOf;
        }
        
    }
    
    //add function to request documents that will throw event on blockchain?
    
    function priceKYCProcess(uint nid, address addr) FI_CHECK public
        view returns (uint[] memory priceList_)
    {
        require(nodeExists(nid), "Process does not exist does not exist");
        uint nodeID = nid;
        uint level = KYCNodes[nodeID].update + 1;
        uint[] memory priceList = new uint[](level); 
        while (level > 0)
        {
            uint price = priceKYC(nodeID);
            if (!isSubscriber(nodeID,addr) && !isParticipant(nodeID,addr))
            {
                priceList[level-1] = price;
            }
            else
            {
                priceList[level-1] = 0;
            }
            nodeID = KYCNodes[nodeID].updateOf;
            level -= 1;
        }
        priceList_ = priceList;
    }
    
    //buy price of node
    function priceKYC(uint nid) FI_CHECK private
        view returns (uint)
    {
        require(nodeExists(nid), "Process does not exist does not exist");
        uint nodeID = nid;
        uint level = KYCNodes[nodeID].update;
        uint cost = updatePrice;
        if (level == 0)
        {
            cost = corePrice;
        }
        uint r = participants[nodeID].length;
        uint p = participants[nodeID].length + subscribers[nodeID].length;
        return (r*cost)/(p+1);
    }
    
    function updateMergeKYCProcess(uint cid, uint nid, uint[] memory nids, 
        bytes32 hash, bool approved) FI_CHECK public
    {
        require(clientExists(cid), "Client does not exist");
        require(nids.length>0,"Must merge with other processes");
        uint update = KYCNodes[nid].update; //nid = 0 does not exist, and will default to zero.
        if (nid != 0)
        {
            update += 1;
        }
        for (uint i = 0; i < nids.length; i+=1)
        {
            uint nodeID = nids[i];
            KYCNode memory node = KYCNodes[nodeID];
            require(nodeExists(nodeID), "A Process does not exist");
            require(node.allowMerge, "A Process does not allow merge");
            require(node.approved == approved, "All process approval status must match");
            require(node.updateOf == nid, "A Process is of a different branch");
            require(node.update == update, "A Process is of a different update level");
            require(!node.merged, "A Process cannot be merged more than once"); //Maybe?
            require(node.minParticipantsForMerge <= nids.length + 1, 
                "Too few processes for merge");
            require(node.maxParticipantsForMerge >= nids.length + 1,  
                "Too many processes for merge");
            require(subscribers[nodeID].length == 0, "A Process cannot have subscribers");
        }
        uint newNodeID = getID();
        for (uint i = 0; i < nids.length; i+=1)
        {
            uint nodeID = nids[i];
            KYCNodes[nodeID].merged = true;
            participants[newNodeID].push(participants[nodeID][0]);
            documentHash[newNodeID].push(documentHash[nodeID][0]);
            for (uint j = 0; j < nids.length; j+=1)
            {
                uint otherID = nids[i];
                if (nodeID != otherID)
                {
                    emit RequestDocuments(participants[otherID][0],
                                          participants[nodeID][0],otherID,
                                          documentHash[otherID][0]);
                }
            }
            emit RequestDocuments(participants[nodeID][0],msg.sender,
                                  nodeID,documentHash[nodeID][0]);
            emit RequestDocuments(msg.sender,participants[nodeID][0],
                                  newNodeID,hash);
        }
        participants[newNodeID].push(msg.sender);
        documentHash[newNodeID].push(hash);
        
        uint lastID = findLastNode(cid);
        KYCNodes[lastID].nextID = newNodeID;
    
        KYCNodes[newNodeID] = KYCNode(newNodeID,approved,NodeStatus.Merge,
                                      update,nid,false,0,0
                                      ,false,lastID,0);
        clients[cid].KYCProcesses += 1;
    }
    
    function listKYCProcesses(uint cid, uint updates) FI_CHECK public
        view returns ( uint[] memory nodeIDs_ )
    {
        require(clientExists(cid), "Client does not exist");
        require(clients[cid].KYCProcesses > 0, 
            "Client have zero KYC processes");
        require(clients[cid].updates >= updates, 
            "No KYC process has been updated that many times");

        uint[] memory nodeIDs = new uint[](clients[cid].KYCProcesses);
        uint curNodeID = clients[cid].KYCNodeID;
        uint nextNodeID = KYCNodes[curNodeID].nextID;
        uint i = 0;
        while (curNodeID != 0)
        {
            if (KYCNodes[curNodeID].update == updates)
            {
                nodeIDs[i] = curNodeID;
                i += 1;
            }
            curNodeID = nextNodeID;
            nextNodeID = KYCNodes[curNodeID].nextID;
        }
        uint[] memory retval = new uint[](i);
        for (uint j = 0; j < i; j+=1) 
        {
            retval[j] = nodeIDs[j];
        }
        nodeIDs_ = retval;
    }
    
    function fetchClient(uint cid) FI_CHECK public
        view returns ( Client memory client_ )
    {
        require(clientExists(cid), "Client does not exist");
        Client memory client = clients[cid];
        client_ = client;
    }
    
    function fetchKYCProcess(uint nid) FI_CHECK public
        view returns ( KYCNode memory node_ )
    {
        require(nodeExists(nid), "Process does not exist");
        KYCNode memory node = KYCNodes[nid];
        node_ = node;
    }
    
    function fetchParticipants(uint nid) FI_CHECK public
        view returns ( address[] memory participants_ )
    {
        require(nodeExists(nid), "Process does not exist");
        address[] memory participant = participants[nid];
        participants_ = participant;
    }
    
    //give client id
    function findLastNode(uint id) private 
        view returns (uint)
    {
        require(clientExists(id), "Client does not exist");
        uint nodeID = clients[id].KYCNodeID;
        bool found = false;
        if (nodeID == 0)
        {
            found = true;
        }
        while (!found)
        {
            uint nextID = KYCNodes[nodeID].nextID;
            if (nextID == 0)
            {
                found = true;
            }
            else 
            {
                nodeID = nextID;
            }
        }
        return nodeID;
    }
}