pragma solidity 0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
contract LFGlobalEscrow is Ownable {
enum Sign {
NULL,
REVERT,
RELEASE
}
struct Record {
string referenceId;
address payable owner;
address payable sender;
address payable receiver;
address payable agent;
uint256 fund;
bool disputed;
bool finalized;
mapping(address => bool) signer;
mapping(address => Sign) signed;
uint256 releaseCount;
uint256 revertCount;
uint256 lastTxBlock;
}
mapping(string => Record) _escrow;
function owner(string memory _referenceId) public view returns
(address payable) {
return _escrow[_referenceId].owner;
}
function sender(string memory _referenceId) public view returns
(address payable) {
return _escrow[_referenceId].sender;

}
function receiver(string memory _referenceId) public view returns
(address payable) {
return _escrow[_referenceId].receiver;
}
function agent(string memory _referenceId) public view returns
(address payable) {
return _escrow[_referenceId].agent;
}
function amount(string memory _referenceId) public view returns
(uint256) {
return _escrow[_referenceId].fund;
}
function isDisputed(string memory _referenceId) public view
returns (bool) {
return _escrow[_referenceId].disputed;
}
function isFinalized(string memory _referenceId) public view
returns (bool) {
return _escrow[_referenceId].finalized;
}
function lastBlock(string memory _referenceId) public view
returns (uint256) {
return _escrow[_referenceId].lastTxBlock;
}
function isSigner(string memory _referenceId, address _signer)
public view returns (bool) {
return _escrow[_referenceId].signer[_signer];
}
function getSignedAction(string memory _referenceId, address
_signer) public view returns (Sign) {
return _escrow[_referenceId].signed[_signer];
}
function releaseCount(string memory _referenceId) public view

returns (uint256) {
return _escrow[_referenceId].releaseCount;
}
function revertCount(string memory _referenceId) public view
returns (uint256) {
return _escrow[_referenceId].revertCount;
}
event Initiated(string referenceId, address payer, uint256
amount, address payee, address trustedParty, uint256 lastBlock);
//event OwnershipTransferred(string referenceIdHash, address
oldOwner, address newOwner, uint256 lastBlock);
event Signature(string referenceId, address signer, Sign action,
uint256 lastBlock);
event Finalized(string referenceId, address winner, uint256
lastBlock);
event Disputed(string referenceId, address disputer, uint256
lastBlock);
event Withdrawn(string referenceId, address payee, uint256
amount, uint256 lastBlock);

modifier multisigcheck(string memory _referenceId) {
Record storage e = _escrow[_referenceId];
require(!e.finalized, "Escrow should not be finalized");
require(e.signer[msg.sender], "msg sender should be eligible
to sign");
require(e.signed[msg.sender] == Sign.NULL, "msg sender should
not have signed already");
_;
if(e.releaseCount == 2) {
transferOwnership(e);
}else if(e.revertCount == 2) {
finalize(e);
}else if(e.releaseCount == 1 && e.revertCount == 1) {
dispute(e);
}
}
function init(string memory _referenceId, address payable
_receiver, address payable _agent) public payable {

require(msg.sender != address(0), "Sender should not be
null");
require(_receiver != address(0), "Receiver should not be
null");
//require(_trustedParty != address(0), "Trusted Agent should
not be null");
emit Initiated(_referenceId, msg.sender, msg.value,
_receiver, _agent, 0);
Record storage e = _escrow[_referenceId];
e.referenceId = _referenceId;
e.owner = payable(msg.sender);
e.sender = payable(msg.sender);
e.receiver = _receiver;
e.agent = _agent;
e.fund = msg.value;
e.disputed = false;
e.finalized = false;
e.lastTxBlock = block.number;
e.releaseCount = 0;
e.revertCount = 0;
_escrow[_referenceId].signer[msg.sender] = true;
_escrow[_referenceId].signer[_receiver] = true;
_escrow[_referenceId].signer[_agent] = true;
}
function release(string memory _referenceId) public
multisigcheck(_referenceId) {
Record storage e = _escrow[_referenceId];
emit Signature(_referenceId, msg.sender, Sign.RELEASE,
e.lastTxBlock);
e.signed[msg.sender] = Sign.RELEASE;
e.releaseCount++;
}
function reverse(string memory _referenceId) public
multisigcheck(_referenceId) {
Record storage e = _escrow[_referenceId];

emit Signature(_referenceId, msg.sender, Sign.REVERT,
e.lastTxBlock);
e.signed[msg.sender] = Sign.REVERT;
e.revertCount++;
}
function dispute(string memory _referenceId) public {
Record storage e = _escrow[_referenceId];
require(!e.finalized, "Escrow should not be finalized");
require(msg.sender == e.sender || msg.sender == e.receiver,
"Only sender or receiver can call dispute");
dispute(e);
}
function transferOwnership(Record storage e) internal {
e.owner = e.receiver;
finalize(e);
e.lastTxBlock = block.number;
}
function dispute(Record storage e) internal {
emit Disputed(e.referenceId, msg.sender, e.lastTxBlock);
e.disputed = true;
e.lastTxBlock = block.number;
}
function finalize(Record storage e) internal {
require(!e.finalized, "Escrow should not be finalized");
emit Finalized(e.referenceId, e.owner, e.lastTxBlock);
e.finalized = true;
}
function withdraw(string memory _referenceId, uint256 _amount)
public {
Record storage e = _escrow[_referenceId];
require(e.finalized, "Escrow should be finalized before
withdrawal");
require(msg.sender == e.owner, "only owner can withdraw

funds");
require(_amount <= e.fund, "cannot withdraw more than the
deposit");
emit Withdrawn(_referenceId, msg.sender, _amount,
e.lastTxBlock);
e.fund = e.fund - _amount;
e.lastTxBlock = block.number;
require((e.owner).send(_amount));
}
}