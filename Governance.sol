// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.7.0 <0.9.0;

contract Governance 
{
    address private MSP;
    address private creatorContract;
    
    modifier MSP_CHECK {
        require(msg.sender == MSP, 
          "Must be MSP to use this function");
        _;
    }
    
    modifier MSP_OR_CREATOR_CHECK {
        require(msg.sender == MSP || msg.sender == creatorContract, 
          "Must be MSP or creator contract to use this function");
        _;
    }
    
    //default maps to false.
    mapping (address => bool) FIs;
    constructor(address _MSP)
    {
        MSP = _MSP;
        creatorContract = msg.sender;
    }

    function addFI(address addr) MSP_CHECK public
    {
        FIs[addr] = true;
    }
    
    function removeFI(address addr) MSP_CHECK public
    {
        FIs[addr] = false;
    }
    
    function checkFI(address addr) MSP_OR_CREATOR_CHECK public
        view returns (bool value_)
    {
        value_ = FIs[addr];
    }
}