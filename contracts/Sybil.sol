// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.6.12;

import "./interfaces/IVerifierRollup.sol";
import "./interfaces/IVerifierWithdrawInterface.sol";
import "./lib/InstantWithdrawManager.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Sybil is InstantWithdrawManager {
    struct VerifierRollup {
        VerifierRollupInterface verifierInterface;
        uint256 maxTx; // maximum rollup transactions in a batch: L2-tx + L1-tx transactions
        uint256 nLevels; // number of levels of the circuit
    }

    // ERC20 signatures:

    // bytes4(keccak256(bytes("transfer(address,uint256)")));
    bytes4 constant _TRANSFER_SIGNATURE = 0xa9059cbb;

    // bytes4(keccak256(bytes("transferFrom(address,address,uint256)")));
    bytes4 constant _TRANSFER_FROM_SIGNATURE = 0x23b872dd;

    // bytes4(keccak256(bytes("approve(address,uint256)")));
    bytes4 constant _APPROVE_SIGNATURE = 0x095ea7b3;

    // ERC20 extensions:

    // bytes4(keccak256(bytes("permit(address,address,uint256,uint256,uint8,bytes32,bytes32)")));
    bytes4 constant _PERMIT_SIGNATURE = 0xd505accf;

    // First 256 indexes reserved, first user index will be the 256
    uint48 constant _RESERVED_IDX = 255;

    // IDX 1 is reserved for exits
    uint48 constant _EXIT_IDX = 1;

    // Max load amount allowed (loadAmount: L1 --> L2)
    uint256 constant _LIMIT_LOAD_AMOUNT = (1 << 128);

    // Max amount allowed (amount L2 --> L2)
    uint256 constant _LIMIT_L2TRANSFER_AMOUNT = (1 << 192);

    // [65 bytes] compressedSignature + [32 bytes] fromBjj-compressed 
    uint256 constant _L1_COORDINATOR_TOTALBYTES = 97;

    // [20 bytes] fromEthAddr + [32 bytes] fromBjj-compressed + [6 bytes] fromIdx +
    // [5 bytes] loadAmountFloat40 + [5 bytes] amountFloat40 + [6 bytes] toIdx
    uint256 constant _L1_USER_TOTALBYTES = 74;

    // User TXs are the TX made by the user with a L1 TX
    // Coordinator TXs are the L2 account creation made by the coordinator whose signature
    // needs to be verified in L1.
    // The maximum number of L1-user TXs and L1-coordinartor-TX is limited by the _MAX_L1_TX
    // And the maximum User TX is _MAX_L1_USER_TX

    // Maximum L1-user transactions allowed to be queued in a batch
    uint256 constant _MAX_L1_USER_TX = 128;

    // Maximum L1 transactions allowed to be queued in a batch
    uint256 constant _MAX_L1_TX = 256;

    // Modulus zkSNARK
    uint256 constant _RFIELD = 21888242871839275222246405745257275088548364400416034343698204186575808495617;

    // [6 bytes] lastIdx + [6 bytes] newLastIdx  + [32 bytes] stateRoot  + [32 bytes] newStRoot  + [32 bytes] newExitRoot +
    // [_MAX_L1_TX * _L1_USER_TOTALBYTES bytes] l1TxsData + totall1L2TxsDataLength + feeIdxCoordinatorLength + [2 bytes] chainID + [4 bytes] batchNum =
    // 18546 bytes + totall1L2TxsDataLength + feeIdxCoordinatorLength

    uint256 constant _INPUT_SHA_CONSTANT_BYTES = 20082;

    uint8 public constant ABSOLUTE_MAX_L1L2BATCHTIMEOUT = 240;

    // This ethereum address is used internally for rollup accounts that don't have ethereum address, only Babyjubjub
    // This non-ethereum accounts can be created by the coordinator and allow users to have a rollup
    // account without needing an ethereum address
    address constant _ETH_ADDRESS_INTERNAL_ONLY = address(
        0xFFfFfFffFFfffFFfFFfFFFFFffFFFffffFfFFFfF
    );

    // Verifiers array
    VerifierRollup[] public rollupVerifiers;

    // Last account index created inside the rollup
    uint48 public lastIdx;

    // Last batch forged
    uint32 public lastForgedBatch;

    // Each batch forged will have a correlated 'state root'
    mapping(uint32 => uint256) public stateRootMap;

    // Each batch forged will have a correlated 'exit tree' represented by the exit root
    mapping(uint32 => uint256) public exitRootsMap;

    // Each batch forged will have a correlated 'l1L2TxDataHash'
    mapping(uint32 => bytes32) public l1L2TxsDataHashMap;

    // Mapping of exit nullifiers, only allowing each withdrawal to be made once
    // rootId => (Idx => true/false)
    mapping(uint32 => mapping(uint48 => bool)) public exitNullifierMap;

    // Mapping of L1 balance
    // address => uint256
    mapping (address => uint) L1BalanceMap;

    // Map of queues of L1-user-tx transactions, the transactions are stored in bytes32 sequentially
    // The coordinator is forced to forge the next queue in the next L1-L2-batch
    mapping(uint32 => bytes) public mapL1TxQueue;

    // Ethereum block where the last L1-L2-batch was forged
    uint64 public lastL1L2Batch;

    // Queue index that will be forged in the next L1-L2-batch
    uint32 public nextL1ToForgeQueue;

    // Queue index wich will be filled with the following L1-User-Tx
    uint32 public nextL1FillingQueue;

    // Max ethereum blocks after the last L1-L2-batch, when exceeds the timeout only L1-L2-batch are allowed
    uint8 public forgeL1L2BatchTimeout;

    // Event emitted when the contract is initialized
    event InitializeSybilEvent(
        uint8 forgeL1L2BatchTimeout
    );

    // Event emitted when a L1-user transaction is called and added to the nextL1FillingQueue queue
    event L1UserTxEvent(
        uint32 indexed queueIndex,
        uint8 indexed position,  // Position inside the queue where the TX resides
        bytes l1UserTx
    );

    // Event emitted every time a batch is forged
    event ForgeBatch(uint32 indexed batchNum, uint16 l1UserTxsLen);

    // event emitted when an L1 deposit is done
    event L1EthDeposit(
        address indexed sender,
        uint256 indexed amount
    );
    // Event emitted when a withdrawal is done
    event WithdrawEvent(
        uint48 indexed idx,
        uint32 indexed numExitRoot,
        bool indexed instantWithdraw
    );

    // Event emitted when the contract is updated to the new version
    event SybilV2();

    function initialize(
        address[] memory _verifiers,
        uint256[] memory _verifiersParams,
        uint8 _forgeL1L2BatchTimeout,
        address _poseidon2Elements,
        address _poseidon3Elements,
        address _poseidon4Elements
    ) external initializer {
        // set state variables
        _initializeVerifiers(_verifiers, _verifiersParams);
        forgeL1L2BatchTimeout = _forgeL1L2BatchTimeout;

        // set default state variables
        lastIdx = _RESERVED_IDX;
        // lastL1L2Batch = 0; // --> first batch forced to be L1Batch
        // nextL1ToForgeQueue = 0; // --> First queue will be forged
        // nextL1FillingQueue = 1;
        stateRootMap[0] = 0; // --> genesis batch will have root = 0

        // initialize libs
        _initializeHelpers(
            _poseidon2Elements,
            _poseidon3Elements,
            _poseidon4Elements
        );

        emit InitializeSybilEvent(
            _forgeL1L2BatchTimeout
        );
    }

    //////////////
    // Coordinator operations
    /////////////

     /**
     * @dev Forge a new batch providing the L2 Transactions, L1Corrdinator transactions and the proof.
     * If the proof is succesfully verified, update the current state, adding a new state and exit root.
     * In order to optimize the gas consumption the parameters `encodedL1CoordinatorTx`, `l1L2TxsData` and `feeIdxCoordinator`
     * are read directly from the calldata using assembly with the instruction `calldatacopy`
     * @param newLastIdx New total rollup accounts
     * @param newStRoot New state root
     * @param newExitRoot New exit root
     * @param encodedL1CoordinatorTx Encoded L1-coordinator transactions
     * @param l1L2TxsData Encoded l2 data
     * @param feeIdxCoordinator Encoded idx accounts of the coordinator where the fees will be payed
     * @param verifierIdx Verifier index
     * @param l1Batch Indicates if this batch will be L2 or L1-L2
     * @param proofA zk-snark input
     * @param proofB zk-snark input
     * @param proofC zk-snark input
     * Events: `ForgeBatch`
     */
    function forgeBatch(
        uint48 newLastIdx,
        uint256 newStRoot,
        uint256 newExitRoot,
        bytes calldata encodedL1CoordinatorTx,
        bytes calldata l1L2TxsData,
        bytes calldata feeIdxCoordinator,
        uint8 verifierIdx,
        bool l1Batch,
        uint256[2] calldata proofA,
        uint256[2][2] calldata proofB,
        uint256[2] calldata proofC
    ) external virtual {
        // Assure data availability from regular ethereum nodes
        // We include this line because it's easier to track the transaction data, as it will never be in an internal TX.
        // In general this makes no sense, as callling this function from another smart contract will have to pay the calldata twice.
        // But forcing, it avoids having to check.
        require(
            msg.sender == tx.origin,
            "Sybil::forgeBatch: INTENAL_TX_NOT_ALLOWED"
        );

        if (!l1Batch) {
            require(
                block.number < (lastL1L2Batch + forgeL1L2BatchTimeout), // No overflow since forgeL1L2BatchTimeout is an uint8
                "Sybil::forgeBatch: L1L2BATCH_REQUIRED"
            );
        }

        // calculate input
        uint256 input = _constructCircuitInput(
            newLastIdx,
            newStRoot,
            newExitRoot,
            l1Batch,
            verifierIdx
        );

        // verify proof
        require(
            rollupVerifiers[verifierIdx].verifierInterface.verifyProof(
                proofA,
                proofB,
                proofC,
                [input]
            ),
            "Sybil::forgeBatch: INVALID_PROOF"
        );

        // update state
        lastForgedBatch++;
        lastIdx = newLastIdx;
        stateRootMap[lastForgedBatch] = newStRoot;
        exitRootsMap[lastForgedBatch] = newExitRoot;
        l1L2TxsDataHashMap[lastForgedBatch] = sha256(l1L2TxsData);


        uint16 l1UserTxsLen;
        if (l1Batch) {
            // restart the timeout
            lastL1L2Batch = uint64(block.number);
            // clear current queue
            l1UserTxsLen = _clearQueue();
        }

        emit ForgeBatch(lastForgedBatch, l1UserTxsLen);
    }

    //////////////
    // User L1 rollup tx
    /////////////

    // This are all the possible L1-User transactions:
    // | fromIdx | toIdx | loadAmountF | amountF | babyPubKey |           l1-user-TX            |
    // |:-------:|:-----:|:-----------:|:-------:|:----------:|:-------------------------------:|
    // |    0    |   0   |      0      |    0    |    !=0     |          createAccount          |
    // |    0    |   0   |     !=0     |    0    |    !=0     |      createAccountDeposit       |
    // |    0    | 255+  |      X      |    X    |    !=0     | createAccountDepositAndTransfer |
    // |  255+   |   0   |      X      |    0    |     0      |             Deposit             |
    // |  255+   |   1   |      0      |    X    |     0      |              Exit               |
    // |  255+   | 255+  |      0      |    X    |     0      |            Transfer             |
    // |  255+   | 255+  |     !=0     |    X    |     0      |       DepositAndTransfer        |
    // As can be seen in the table the type of transaction is determined basically by the "fromIdx" and "toIdx"
    // The 'X' means that can be any valid value and does not change the l1-user-tx type
    // Other parameters must be consistent, for example, if toIdx is 0, amountF must be 0, because there's no L2 transfer

    /**
     * @dev Create a new rollup l1 user transaction
     * @param babyPubKey Public key babyjubjub represented as point: sign + (Ay)
     * @param fromIdx Index leaf of sender account or 0 if create new account
     * @param loadAmountF Amount from L1 to L2 to sender account or new account
     * @param amountF Amount transfered between L2 accounts
     * @param toIdx Index leaf of recipient account, or _EXIT_IDX if exit, or 0 if not transfer
     * Events: `L1UserTxEvent`
     */
    function addL1Transaction(
        uint256 babyPubKey,
        uint48 fromIdx,
        uint40 loadAmountF,
        uint40 amountF,
        uint48 toIdx
    ) external payable {
        // check loadAmount
        uint256 loadAmount = _float2Fix(loadAmountF);
        require(
            loadAmount < _LIMIT_LOAD_AMOUNT,
            "Sybil::addL1Transaction: LOADAMOUNT_EXCEED_LIMIT"
        );

        // verify deposit ether
        if (loadAmount > 0) {
            require(
                loadAmount == msg.value,
                "Sybil::addL1Transaction: LOADAMOUNT_ETH_DOES_NOT_MATCH"
            );            
        }

        // perform L1 User Tx
        _addL1Transaction(
            msg.sender,
            babyPubKey,
            fromIdx,
            loadAmountF,
            amountF,
            toIdx
        );
    }

    /**
     * @dev Create a new rollup l1 user transaction
     * @param ethAddress Ethereum addres of the sender account or new account
     * @param babyPubKey Public key babyjubjub represented as point: sign + (Ay)
     * @param fromIdx Index leaf of sender account or 0 if create new account
     * @param loadAmountF Amount from L1 to L2 to sender account or new account
     * @param amountF Amount transfered between L2 accounts
     * @param toIdx Index leaf of recipient account, or _EXIT_IDX if exit, or 0 if not transfer
     * Events: `L1UserTxEvent`
     */
    function _addL1Transaction(
        address ethAddress,
        uint256 babyPubKey,
        uint48 fromIdx,
        uint40 loadAmountF,
        uint40 amountF,
        uint48 toIdx
    ) internal {
        // check amount
        uint256 amount = _float2Fix(amountF);
        require(
            amount < _LIMIT_L2TRANSFER_AMOUNT,
            "Sybil::_addL1Transaction: AMOUNT_EXCEED_LIMIT"
        );

        // toIdx can be: 0, _EXIT_IDX or (toIdx > _RESERVED_IDX)
        if (toIdx == 0) {
            require(
                (amount == 0),
                "Sybil::_addL1Transaction: AMOUNT_MUST_BE_0_IF_NOT_TRANSFER"
            );
        } else {
            if ((toIdx == _EXIT_IDX)) {
                require(
                    (loadAmountF == 0),
                    "Sybil::_addL1Transaction: LOADAMOUNT_MUST_BE_0_IF_EXIT"
                );
            } else {
                require(
                    ((toIdx > _RESERVED_IDX) && (toIdx <= lastIdx)),
                    "Sybil::_addL1Transaction: INVALID_TOIDX"
                );
            }
        }

        // fromIdx can be: 0 if create account or (fromIdx > _RESERVED_IDX)
        if (fromIdx == 0) {
            require(
                babyPubKey != 0,
                "Sybil::_addL1Transaction: INVALID_CREATE_ACCOUNT_WITH_NO_BABYJUB"
            );
        } else {
            require(
                (fromIdx > _RESERVED_IDX) && (fromIdx <= lastIdx),
                "Sybil::_addL1Transaction: INVALID_FROMIDX"
            );
            require(
                babyPubKey == 0,
                "Sybil::_addL1Transaction: BABYJUB_MUST_BE_0_IF_NOT_CREATE_ACCOUNT"
            );
        }

        _l1QueueAddTx(
            ethAddress,
            babyPubKey,
            fromIdx,
            loadAmountF,
            amountF,
            toIdx
        );
    }

    //////////////
    // User operations
    /////////////

    function depositL1Eth() payable external {
        L1BalanceMap[msg.sender] += msg.value;
        emit L1EthDeposit(msg.sender, msg.value);
    }

    /**
     * @dev Withdraw to retrieve the tokens from the exit tree to the owner account
     * Before this call an exit transaction must be done
     * @param amount Amount to retrieve
     * @param babyPubKey Public key babyjubjub represented as point: sign + (Ay)
     * @param numExitRoot Batch number where the exit transaction has been done
     * @param siblings Siblings to demonstrate merkle tree proof
     * @param idx Index of the exit tree account
     * @param instantWithdraw true if is an instant withdraw
     * Events: `WithdrawEvent`
     */
    function withdrawMerkleProof(
        uint192 amount,
        uint256 babyPubKey,
        uint32 numExitRoot,
        uint256[] memory siblings,
        uint48 idx,
        bool instantWithdraw
    ) external {
        // require(L1BalanceMap[msg.sender] >= amount,
        //     "Sybil::withdrawMerkleProof: INSUFFICIENT_BALANCE"
        // );
        // numExitRoot is not checked because an invalid numExitRoot will bring to a 0 root
        // and this is an empty tree.
        // in case of instant withdraw assure that is available
        if (instantWithdraw) {
            require(
                _processInstantWithdrawal(address(0), amount),
                "Sybil::withdrawMerkleProof: INSTANT_WITHDRAW_WASTED_FOR_THIS_USD_RANGE"
            );
        }

        // build 'key' and 'value' for exit tree
        uint256[4] memory arrayState = _buildTreeState(
            0,
            0,
            amount,
            babyPubKey,
            msg.sender
        );
        uint256 stateHash = _hash4Elements(arrayState);
        // get exit root given its index depth
        uint256 exitRoot = exitRootsMap[numExitRoot];
        // check exit tree nullifier
        require(
            exitNullifierMap[numExitRoot][idx] == false,
            "Sybil::withdrawMerkleProof: WITHDRAW_ALREADY_DONE"
        );
        // check sparse merkle tree proof
        require(
            _smtVerifier(exitRoot, siblings, idx, stateHash) == true,
            "Sybil::withdrawMerkleProof: SMT_PROOF_INVALID"
        );

        // set nullifier
        exitNullifierMap[numExitRoot][idx] = true;

        // update balance
        _withdrawFunds(amount, 0);
        L1BalanceMap[msg.sender] -= amount;

        emit WithdrawEvent(idx, numExitRoot, instantWithdraw);
    }

    /**
     * @dev Initialize verifiers
     * @param _verifiers verifiers address array
     * @param _verifiersParams encoeded maxTx and nlevels of the verifier as follows:
     * [8 bits]nLevels || [248 bits] maxTx
     */
    function _initializeVerifiers(
        address[] memory _verifiers,
        uint256[] memory _verifiersParams
    ) internal {
        for (uint256 i = 0; i < _verifiers.length; i++) {
            rollupVerifiers.push(
                VerifierRollup({
                    verifierInterface: VerifierRollupInterface(_verifiers[i]),
                    maxTx: (_verifiersParams[i] << 8) >> 8,
                    nLevels: _verifiersParams[i] >> (256 - 8)
                })
            );
        }
    }

    /**
     * @dev Add L1-user-tx, add it to the correspoding queue
     * l1Tx L1-user-tx encoded in bytes as follows: [20 bytes] fromEthAddr || [32 bytes] fromBjj-compressed || [4 bytes] fromIdx ||
     * [5 bytes] loadAmountFloat40 || [5 bytes] amountFloat40 || [4 bytes] toIdx
     * @param ethAddress Ethereum address of the rollup account
     * @param babyPubKey Public key babyjubjub represented as point: sign + (Ay)
     * @param fromIdx Index account of the sender account
     * @param loadAmountF Amount from L1 to L2
     * @param amountF  Amount transfered between L2 accounts
     * @param toIdx Index leaf of recipient account
     * Events: `L1UserTxEvent`
     */
    function _l1QueueAddTx(
        address ethAddress,
        uint256 babyPubKey,
        uint48 fromIdx,
        uint40 loadAmountF,
        uint40 amountF,
        uint48 toIdx
    ) internal {
        bytes memory l1Tx = abi.encodePacked(
            ethAddress,
            babyPubKey,
            fromIdx,
            loadAmountF,
            amountF,
            toIdx
        );

        uint256 currentPosition = mapL1TxQueue[nextL1FillingQueue].length /
            _L1_USER_TOTALBYTES;

        // concatenate storage byte array with the new l1Tx
        _concatStorage(mapL1TxQueue[nextL1FillingQueue], l1Tx);

        emit L1UserTxEvent(nextL1FillingQueue, uint8(currentPosition), l1Tx);

        if (currentPosition + 1 >= _MAX_L1_USER_TX) {
            nextL1FillingQueue++;
        }
    }

    /**
     * @dev Calculate the circuit input hashing all the elements
     * @param newLastIdx New total rollup accounts
     * @param newStRoot New state root
     * @param newExitRoot New exit root
     * @param l1Batch Indicates if this forge will be L2 or L1-L2
     * @param verifierIdx Verifier index
     */
    function _constructCircuitInput(
        uint48 newLastIdx,
        uint256 newStRoot,
        uint256 newExitRoot,
        bool l1Batch,
        uint8 verifierIdx
    ) internal view returns (uint256) {
        uint256 oldStRoot = stateRootMap[lastForgedBatch];
        uint256 oldLastIdx = lastIdx;
        uint256 dPtr; // Pointer to the calldata parameter data
        uint256 dLen; // Length of the calldata parameter

        // l1L2TxsData = l2Bytes * maxTx =
        // ([(nLevels / 8) bytes] fromIdx + [(nLevels / 8) bytes] toIdx + [5 bytes] amountFloat40 + [1 bytes] fee) * maxTx =
        // ((nLevels / 4) bytes + 3 bytes) * maxTx
        uint256 l1L2TxsDataLength = ((rollupVerifiers[verifierIdx].nLevels /
            8) *
            2 +
            5 +
            1) * rollupVerifiers[verifierIdx].maxTx;

        // [(nLevels / 8) bytes]
        uint256 feeIdxCoordinatorLength = (rollupVerifiers[verifierIdx]
            .nLevels / 8) * 64;

        // the concatenation of all arguments could be done with abi.encodePacked(args), but is suboptimal, especially with a large bytes arrays
        // [6 bytes] lastIdx +
        // [6 bytes] newLastIdx  +
        // [32 bytes] stateRoot  +
        // [32 bytes] newStRoot  +
        // [32 bytes] newExitRoot +
        // [_MAX_L1_TX * _L1_USER_TOTALBYTES bytes] l1TxsData +
        // totall1L2TxsDataLength +
        // feeIdxCoordinatorLength +
        // [2 bytes] chainID +
        // [4 bytes] batchNum =
        // _INPUT_SHA_CONSTANT_BYTES bytes +  totall1L2TxsDataLength + feeIdxCoordinatorLength
        bytes memory inputBytes;

        uint256 ptr; // Position for writing the bufftr

        assembly {
            let inputBytesLength := add(
                add(_INPUT_SHA_CONSTANT_BYTES, l1L2TxsDataLength),
                feeIdxCoordinatorLength
            )

            // Set inputBytes to the next free memory space
            inputBytes := mload(0x40)
            // Reserve the memory. 32 for the length , the input bytes and 32
            // extra bytes at the end for word manipulation
            mstore(0x40, add(add(inputBytes, 0x40), inputBytesLength))

            // Set the actual length of the input bytes
            mstore(inputBytes, inputBytesLength)

            // Set The Ptr at the begining of the inputPubber
            ptr := add(inputBytes, 32)

            mstore(ptr, shl(208, oldLastIdx)) // 256-48 = 208
            ptr := add(ptr, 6)

            mstore(ptr, shl(208, newLastIdx)) // 256-48 = 208
            ptr := add(ptr, 6)

            mstore(ptr, oldStRoot)
            ptr := add(ptr, 32)

            mstore(ptr, newStRoot)
            ptr := add(ptr, 32)

            mstore(ptr, newExitRoot)
            ptr := add(ptr, 32)
        }

        // Copy the L1TX Data
        _buildL1Data(ptr, l1Batch);
        ptr += _MAX_L1_TX * _L1_USER_TOTALBYTES;

        // Copy the L2 TX Data from calldata
        (dPtr, dLen) = _getCallData(4);
        require(
            dLen <= l1L2TxsDataLength,
            "Sybil::_constructCircuitInput: L2_TX_OVERFLOW"
        );
        assembly {
            calldatacopy(ptr, dPtr, dLen)
        }
        ptr += dLen;

        // L2 TX unused data is padded with 0 at the end
        _fillZeros(ptr, l1L2TxsDataLength - dLen);
        ptr += l1L2TxsDataLength - dLen;

        // Copy the FeeIdxCoordinator from the calldata
        (dPtr, dLen) = _getCallData(5);
        require(
            dLen <= feeIdxCoordinatorLength,
            "Sybil::_constructCircuitInput: INVALID_FEEIDXCOORDINATOR_LENGTH"
        );
        assembly {
            calldatacopy(ptr, dPtr, dLen)
        }
        ptr += dLen;
        _fillZeros(ptr, feeIdxCoordinatorLength - dLen);
        ptr += feeIdxCoordinatorLength - dLen;

        // store 2 bytes of chainID at the end of the inputBytes
        assembly {
            mstore(ptr, shl(240, chainid())) // 256 - 16 = 240
        }
        ptr += 2;

        uint256 batchNum = lastForgedBatch + 1;

        // store 4 bytes of batch number at the end of the inputBytes
        assembly {
            mstore(ptr, shl(224, batchNum)) // 256 - 32 = 224
        }

        return uint256(sha256(inputBytes)) % _RFIELD;
    }

    /**
     * @dev Clear the current queue, and update the `nextL1ToForgeQueue` and `nextL1FillingQueue` if needed
     */
    function _clearQueue() internal returns (uint16) {
        uint16 l1UserTxsLen = uint16(
            mapL1TxQueue[nextL1ToForgeQueue].length / _L1_USER_TOTALBYTES
        );
        delete mapL1TxQueue[nextL1ToForgeQueue];
        nextL1ToForgeQueue++;
        if (nextL1ToForgeQueue == nextL1FillingQueue) {
            nextL1FillingQueue++;
        }
        return l1UserTxsLen;
    }

    /**
     * @dev Withdraw the funds to the msg.sender if instant withdraw or to the withdraw delayer if delayed
     * @param amount Amount to retrieve
     * @param tokenID Token identifier
     */
    function _withdrawFunds(
        uint192 amount,
        uint32 tokenID
    ) internal {
        _safeTransfer(address(0), msg.sender, amount);
    }


    /**
     * @dev return the current L1-user-tx queue adding the L1-coordinator-tx
     * @param ptr Ptr where L1 data is set
     * @param l1Batch if true, the include l1TXs from the queue
     * [1 byte] V(ecdsa signature) || [32 bytes] S(ecdsa signature) ||
     * [32 bytes] R(ecdsa signature) || [32 bytes] fromBjj-compressed
     */
    function _buildL1Data(uint256 ptr, bool l1Batch) internal view {
        uint256 dPtr;
        uint256 dLen;

        (dPtr, dLen) = _getCallData(3);
        uint256 l1CoordinatorLength = dLen / _L1_COORDINATOR_TOTALBYTES;

        uint256 l1UserLength;
        bytes memory l1UserTxQueue;
        if (l1Batch) {
            l1UserTxQueue = mapL1TxQueue[nextL1ToForgeQueue];
            l1UserLength = l1UserTxQueue.length / _L1_USER_TOTALBYTES;
        } else {
            l1UserLength = 0;
        }

        require(
            l1UserLength + l1CoordinatorLength <= _MAX_L1_TX,
            "Sybil::_buildL1Data: L1_TX_OVERFLOW"
        );

        if (l1UserLength > 0) {
            // Copy the queue to the ptr and update ptr
            assembly {
                let ptrFrom := add(l1UserTxQueue, 0x20)
                let ptrTo := ptr
                ptr := add(ptr, mul(l1UserLength, _L1_USER_TOTALBYTES))
                for {

                } lt(ptrTo, ptr) {
                    ptrTo := add(ptrTo, 32)
                    ptrFrom := add(ptrFrom, 32)
                } {
                    mstore(ptrTo, mload(ptrFrom))
                }
            }
        }

        for (uint256 i = 0; i < l1CoordinatorLength; i++) {
            uint8 v; // L1-Coordinator-Tx bytes[0]
            bytes32 s; // L1-Coordinator-Tx bytes[1:32]
            bytes32 r; // L1-Coordinator-Tx bytes[33:64]
            bytes32 babyPubKey; // L1-Coordinator-Tx bytes[65:96]

            assembly {
                v := byte(0, calldataload(dPtr))
                dPtr := add(dPtr, 1)

                s := calldataload(dPtr)
                dPtr := add(dPtr, 32)

                r := calldataload(dPtr)
                dPtr := add(dPtr, 32)

                babyPubKey := calldataload(dPtr)
                dPtr := add(dPtr, 32)
            }

            address ethAddress = _ETH_ADDRESS_INTERNAL_ONLY;

            // v must be >=27 --> EIP-155, v == 0 means no signature
            if (v != 0) {
                ethAddress = _checkSig(babyPubKey, r, s, v);
            }

            // add L1-Coordinator-Tx to the L1-tx queue
            assembly {
                mstore(ptr, shl(96, ethAddress)) // 256 - 160 = 96, write ethAddress: bytes[0:19]
                ptr := add(ptr, 20)

                mstore(ptr, babyPubKey) // write babyPubKey: bytes[20:51]
                ptr := add(ptr, 32)

                mstore(ptr, 0) // write zeros
                // [6 Bytes] fromIdx ,
                // [5 bytes] loadAmountFloat40 .
                // [5 bytes] amountFloat40
                ptr := add(ptr, 16)

                mstore(ptr, 0) // write [6 Bytes] toIdx
                ptr := add(ptr, 6)
            }
        }

        _fillZeros(
            ptr,
            (_MAX_L1_TX - l1UserLength - l1CoordinatorLength) *
                _L1_USER_TOTALBYTES
        );
    }

    ///////////
    // helpers ERC20 functions
    ///////////

    /**
     * @dev Approve ERC20
     * @param token Token address
     * @param to Recievers
     * @param value Quantity of tokens to approve
     */
    function _safeApprove(
        address token,
        address to,
        uint256 value
    ) internal {
        /* solhint-disable avoid-low-level-calls */
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(_APPROVE_SIGNATURE, to, value)
        );
        require(
            success && (data.length == 0 || abi.decode(data, (bool))),
            "Sybil::_safeApprove: ERC20_APPROVE_FAILED"
        );
    }

    /**
     * @dev Transfer tokens or ether from the smart contract
     * @param token Token address
     * @param to Address to recieve the tokens
     * @param value Quantity to transfer
     */
    function _safeTransfer(
        address token,
        address to,
        uint256 value
    ) internal {
        // address 0 is reserved for eth
        if (token == address(0)) {
            /* solhint-disable avoid-low-level-calls */
            (bool success, ) = msg.sender.call{value: value}(new bytes(0));
            require(success, "Sybil::_safeTransfer: ETH_TRANSFER_FAILED");
        } else {
            /* solhint-disable avoid-low-level-calls */
            (bool success, bytes memory data) = token.call(
                abi.encodeWithSelector(_TRANSFER_SIGNATURE, to, value)
            );
            require(
                success && (data.length == 0 || abi.decode(data, (bool))),
                "Sybil::_safeTransfer: ERC20_TRANSFER_FAILED"
            );
        }
    }

    /**
     * @dev transferFrom ERC20
     * Require approve tokens for this contract previously
     * @param token Token address
     * @param from Sender
     * @param to Reciever
     * @param value Quantity of tokens to send
     */
    function _safeTransferFrom(
        address token,
        address from,
        address to,
        uint256 value
    ) internal {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(_TRANSFER_FROM_SIGNATURE, from, to, value)
        );
        require(
            success && (data.length == 0 || abi.decode(data, (bool))),
            "Sybil::_safeTransferFrom: ERC20_TRANSFERFROM_FAILED"
        );
    }

    ///////////
    // helpers ERC20 extension functions
    ///////////

    /**
     * @notice Function to call token permit method of extended ERC20
     * @param _amount Quantity that is expected to be allowed
     * @param _permitData Raw data of the call `permit` of the token
     */
    function _permit(
        address token,
        uint256 _amount,
        bytes calldata _permitData
    ) internal {
        bytes4 sig = abi.decode(_permitData, (bytes4));
        require(
            sig == _PERMIT_SIGNATURE,
            "Sybil::_permit: NOT_VALID_CALL"
        );
        (
            address owner,
            address spender,
            uint256 value,
            uint256 deadline,
            uint8 v,
            bytes32 r,
            bytes32 s
        ) = abi.decode(
            _permitData[4:],
            (address, address, uint256, uint256, uint8, bytes32, bytes32)
        );
        require(
            owner == msg.sender,
            "Sybil::_permit: PERMIT_OWNER_MUST_BE_THE_SENDER"
        );
        require(
            spender == address(this),
            "Sybil::_permit: SPENDER_MUST_BE_THIS"
        );
        require(
            value == _amount,
            "Sybil::_permit: PERMIT_AMOUNT_DOES_NOT_MATCH"
        );

        // we call without checking the result, in case it fails and he doesn't have enough balance
        // the following transferFrom should be fail. This prevents DoS attacks from using a signature
        // before the smartcontract call
        /* solhint-disable avoid-low-level-calls */
        address(token).call(
            abi.encodeWithSelector(
                _PERMIT_SIGNATURE,
                owner,
                spender,
                value,
                deadline,
                v,
                r,
                s
            )
        );
    }
}
