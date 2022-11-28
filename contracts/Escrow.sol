// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

/// @dev No need to import a library we don't use
// import "@openzeppelin/contracts/access/Ownable.sol";

contract LFGlobalEscrow {
    enum Sign {
        NULL,
        REVERT,
        RELEASE
    }

    /// @dev in the matter of Higher-order byte clean storage we sort variables that fills 32bytes slots
    /// @dev No need for agent address to be payable as it won't be owner at all
    struct Record {
        string referenceId; 
        uint256 releaseCount; 
        uint256 revertCount; 
        uint256 lastTxBlock; 
        uint256 fund; 
        mapping(address => bool) signer; 
        mapping(address => Sign) signed; 
        address payable owner; 
        address payable sender; 
        address payable receiver; 
        address agent; 
        bool disputed;
        bool finalized;
    }

    mapping(string => Record) _escrow;

    ///@dev Events come before functions in solidity style guide
    event Initiated(
        string referenceId,
        address payer,
        uint256 amount,
        address payee,
        address trustedParty,
        uint256 lastBlock
    );

    event OwnershipTransferred(
        string referenceIdHash,
        address oldOwner,
        address newOwner,
        uint256 lastBlock
    );

    event Signature(
        string referenceId,
        address signer,
        Sign action,
        uint256 lastBlock
    );

    event Finalized(string referenceId, address winner, uint256 lastBlock);

    event Disputed(string referenceId, address disputer, uint256 lastBlock);

    event Withdrawn(
        string referenceId,
        address payee,
        uint256 amount,
        uint256 lastBlock
    );

    modifier multisigcheck(string calldata _referenceId) {
        Record storage e = _escrow[_referenceId];
        require(!e.finalized, "Escrow should not be finalized");
        require(e.signer[msg.sender], "msg sender should be eligible to sign");
        require(
            e.signed[msg.sender] == Sign.NULL,
            "msg sender should not have signed already"
        );
        _;
        if (e.releaseCount == 2) {
            _transferOwnership(e);
        } else if (e.revertCount == 2) {
            _finalize(e);
        } else if (e.releaseCount == 1 && e.revertCount == 1) {
            _dispute(e);
        }
    }

    ///@dev we sort functions by external -> public -> internal -> private
    ///@dev use calldata as data is readonly instead of memory

    ///@dev it is better to use transfer or low level call instead of send and for this case transfer is good enough
    ///@dev emit event after withdraw
    function withdraw(string calldata _referenceId, uint256 _amount) external {
        Record storage e = _escrow[_referenceId];
        require(e.finalized, "Escrow should be finalized before withdrawal");
        require(msg.sender == e.owner, "only owner can withdraw funds");
        require(_amount <= e.fund, "cannot withdraw more than the deposit");
        e.fund -= _amount;
        e.lastTxBlock = block.number;
        e.owner.transfer(_amount);
        emit Withdrawn(_referenceId, msg.sender, _amount, e.lastTxBlock);
    }

    ///@dev emit event after the release
    ///@dev release better to be external
    function release(
        string calldata _referenceId
    ) external multisigcheck(_referenceId) {
        Record storage e = _escrow[_referenceId];
        e.signed[msg.sender] = Sign.RELEASE;
        e.releaseCount++;
        emit Signature(_referenceId, msg.sender, Sign.RELEASE, e.lastTxBlock);
    }

    ///@dev reverse better to be external
    ///@dev emit event after the reverse
    function reverse(
        string calldata _referenceId
    ) external multisigcheck(_referenceId) {
        Record storage e = _escrow[_referenceId];
        e.signed[msg.sender] = Sign.REVERT;
        e.revertCount++;
        emit Signature(_referenceId, msg.sender, Sign.REVERT, e.lastTxBlock);
    }

    ///@dev should check if disputed
    ///@dev dispute better to be external
    ///@dev Whether the caller is Receiver or Sender should have signed already to let agent dispute the escrow
    function dispute(string calldata _referenceId) external {
        Record storage e = _escrow[_referenceId];
        require(!e.finalized, "Escrow should not be finalized");
        require(!e.disputed, "Escrow should not be disputed");
        require(
            msg.sender == e.sender || msg.sender == e.receiver,
            "Only sender or receiver can call dispute"
        );
        require(
            e.signed[msg.sender] == Sign.REVERT || e.signed[msg.sender] == Sign.RELEASE,
            "msg sender should have signed already"
        );
        _dispute(e);
    }

    function owner(
        string calldata _referenceId
    ) public view returns (address payable) {
        return _escrow[_referenceId].owner;
    }

    function sender(
        string calldata _referenceId
    ) public view returns (address payable) {
        return _escrow[_referenceId].sender;
    }

    function receiver(
        string calldata _referenceId
    ) public view returns (address payable) {
        return _escrow[_referenceId].receiver;
    }

    function agent(
        string calldata _referenceId
    ) public view returns (address) {
        return _escrow[_referenceId].agent;
    }

    function amount(
        string calldata _referenceId
    ) public view returns (uint256) {
        return _escrow[_referenceId].fund;
    }

    function isDisputed(
        string calldata _referenceId
    ) public view returns (bool) {
        return _escrow[_referenceId].disputed;
    }

    function isFinalized(
        string calldata _referenceId
    ) public view returns (bool) {
        return _escrow[_referenceId].finalized;
    }

    function lastBlock(
        string calldata _referenceId
    ) public view returns (uint256) {
        return _escrow[_referenceId].lastTxBlock;
    }

    function isSigner(
        string calldata _referenceId,
        address _signer
    ) public view returns (bool) {
        return _escrow[_referenceId].signer[_signer];
    }

    function getSignedAction(
        string calldata _referenceId,
        address _signer
    ) public view returns (Sign) {
        return _escrow[_referenceId].signed[_signer];
    }

    function releaseCount(
        string calldata _referenceId
    ) public view returns (uint256) {
        return _escrow[_referenceId].releaseCount;
    }

    function revertCount(
        string calldata _referenceId
    ) public view returns (uint256) {
        return _escrow[_referenceId].revertCount;
    }

    ///@dev emit event after the Record initiation
    ///@dev change mapping declaration with pointer storage
    ///@dev change to _agent address
    ///@dev agent should not be allowed to sign before dispute happen
    function init(
        string calldata _referenceId,
        address payable _receiver,
        address payable _agent
    ) public payable {
        require(msg.sender != address(0), "Sender should not be null");
        require(_receiver != address(0), "Receiver should not be null");
        require(_agent != address(0), "Trusted Agent should not be null");

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
        e.signer[msg.sender] = true;
        e.signer[_receiver] = true;
        e.signer[_agent] = false;
        emit Initiated(
            _referenceId,
            msg.sender,
            msg.value,
            _receiver,
            _agent,
            0
        );
    }

    ///@dev rename it so that if we use ownable library (which we don't right now) it has same name functions
    ///@dev emit event after dispute
    ///@dev release better to be private because contract has no inheritance
    ///@dev it is better to modify variable then finalize
    ///@dev better to move e.lastTxBlock = block.number; to finalize to set in both finalize and transferOwnership
    function _transferOwnership(Record storage e) private {
        e.owner = e.receiver;
        _finalize(e);
    }

    ///@dev emit event after dispute
    ///@dev release better to be private because contract has no inheritance
    ///@dev after there is a dispute _agent can do the last vote on revert or release
    function _dispute(Record storage e) private {
        e.disputed = true;
        e.signer[e.agent] = true;
        e.lastTxBlock = block.number;
        emit Disputed(e.referenceId, msg.sender, e.lastTxBlock);
    }

    ///@dev emit event after finalize
    ///@dev finalize better to be private because contract has no inheritance
    function _finalize(Record storage e) private {
        require(!e.finalized, "Escrow should not be finalized");
        e.finalized = true;        
        e.lastTxBlock = block.number;
        emit Finalized(e.referenceId, e.owner, e.lastTxBlock);
    }


}
