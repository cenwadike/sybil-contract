// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.24;

// Uncomment this line to use console.log
// import "hardhat/console.sol";
import "./interfaces/IVerifierRollup.sol";
import "./interfaces/IVerifierWithdrawInterface.sol";
import "./lib/SybilHelpers.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Sybil is SybilHelpers {
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

    // [65 bytes] compressedSignature + [32 bytes] fromBjj-compressed + [4 bytes] tokenId
    uint256 constant _L1_COORDINATOR_TOTALBYTES = 101;

    // [20 bytes] fromEthAddr + [32 bytes] fromBjj-compressed + [6 bytes] fromIdx +
    // [5 bytes] loadAmountFloat40 + [5 bytes] amountFloat40 + [4 bytes] tokenId + [6 bytes] toIdx
    uint256 constant _L1_USER_TOTALBYTES = 78;

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

    // contract admin
    address public owner;

    // Event emitted when the contract is initialized
    event InitializeHermezEvent(
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

    // Event emitted when a withdrawal is done
    event WithdrawEvent(
        uint48 indexed idx,
        uint32 indexed numExitRoot,
        bool indexed instantWithdraw
    );

    // Event emitted when the contract is updated to the new version
    event hermezV2();

    function initialize(
        address[] memory _verifiers,
        uint256[] memory _verifiersParams,
        uint8 _forgeL1L2BatchTimeout,
        address _poseidon2Elements,
        address _poseidon3Elements,
        address _poseidon4Elements
    ) external initializer {
        // set admin state variable
        owner = address(msg.sender);

        // set state variables
        _initializeVerifiers(_verifiers, _verifiersParams);
        forgeL1L2BatchTimeout = _forgeL1L2BatchTimeout;

        // set default state variables
        lastIdx = _RESERVED_IDX;
        lastL1L2Batch = 0; // --> first batch forced to be L1Batch
        nextL1ToForgeQueue = 0; // --> First queue will be forged
        nextL1FillingQueue = 1;
        stateRootMap[0] = 0; // --> genesis batch will have root = 0

        // initialize libs
        _initializeHelpers(
            _poseidon2Elements,
            _poseidon3Elements,
            _poseidon4Elements
        );
        emit InitializeHermezEvent(
            _forgeL1L2BatchTimeout
        );
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
}
