// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.7.0 <0.9.0;


contract PayToken 
{
    address private MSP;
    address private creatorContract;
    
    modifier MSP_CHECK {
        require(msg.sender == MSP, 
          "Must be MSP to use this function");
        _;
    }
    
    modifier CREATOR_CHECK {
        require(msg.sender == creatorContract, 
          "Must be creator to use this function");
        _;
    }
    
    mapping (address => uint) private balance;
    mapping (address => uint) private lockedBalance;
    
    constructor(address _MSP) 
    {
        MSP = _MSP;
        creatorContract = msg.sender;
    }
    
    function showBalance(address addr) 
        public MSP_CHECK view returns (uint value_)
    {
        value_ = balance[addr];
    }
    
    function showLockedBalance(address addr) 
        public MSP_CHECK view returns (uint value_)
    {
        value_ = lockedBalance[addr];
    }
    
    function giveTokens(address addr, 
        uint amount) public MSP_CHECK
    {
        balance[addr] += amount;
    }
    
    function removeTokens(address addr, 
        uint amount) public MSP_CHECK
    {
        balance[addr] -= amount;
    }
    
    function lockTokens(address addr, 
        uint amount) public MSP_CHECK
    {
        require(balance[addr] >= amount);
        balance[addr] -= amount;
        lockedBalance[addr] += amount;
    }
    
    function unlockTokens(address addr, 
        uint amount) public MSP_CHECK
    {
        require(lockedBalance[addr] >= amount);
        lockedBalance[addr] -= amount;
        balance[addr] += amount;
    }
    
    function transferTokens(address from, 
        address to, uint amount) public CREATOR_CHECK 
    {
        require(balance[from] >= amount);
        balance[from] -= amount;
        balance[to] += amount;
    }
}