// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.24;

import "@openzeppelin/contracts/proxy/utils/Initializable.sol";

/**
 * @dev Interface poseidon hash function 2 elements
 */
contract PoseidonUnit2 {
    function poseidon(uint256[2] memory) public pure returns (uint256) {}
}

/**
 * @dev Interface poseidon hash function 3 elements
 */
contract PoseidonUnit3 {
    function poseidon(uint256[3] memory) public pure returns (uint256) {}
}

/**
 * @dev Interface poseidon hash function 4 elements
 */
contract PoseidonUnit4 {
    function poseidon(uint256[4] memory) public pure returns (uint256) {}
}

/**
 * @dev Rollup helper functions
 */
contract SybilHelpers is Initializable {
    PoseidonUnit2 _insPoseidonUnit2;
    PoseidonUnit3 _insPoseidonUnit3;
    PoseidonUnit4 _insPoseidonUnit4;

    uint256 private constant _WORD_SIZE = 32;

    // bytes32 public constant EIP712DOMAIN_HASH =
    //      keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)")
    bytes32 public constant EIP712DOMAIN_HASH =
        0x8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f;

    // bytes32 public constant NAME_HASH =
    //      keccak256("Hermez Network")
    bytes32 public constant NAME_HASH =
        0xbe287413178bfeddef8d9753ad4be825ae998706a6dabff23978b59dccaea0ad;

    // bytes32 public constant VERSION_HASH =
    //      keccak256("1")
    bytes32 public constant VERSION_HASH =
        0xc89efdaa54c0f20c7adf612882df0950f5a951637e0307cdcb4c672f298b8bc6;

    // bytes32 public constant AUTHORISE_TYPEHASH =
    //      keccak256("Authorise(string Provider,string Authorisation,bytes32 BJJKey)");
    bytes32 public constant AUTHORISE_TYPEHASH =
        0xafd642c6a37a2e6887dc4ad5142f84197828a904e53d3204ecb1100329231eaa;
   
    // bytes32 public constant HERMEZ_NETWORK_HASH = keccak256(bytes("Hermez Network")),
    bytes32 public constant HERMEZ_NETWORK_HASH =
        0xbe287413178bfeddef8d9753ad4be825ae998706a6dabff23978b59dccaea0ad;
    
    // bytes32 public constant ACCOUNT_CREATION_HASH = keccak256(bytes("Account creation")),
    bytes32 public constant ACCOUNT_CREATION_HASH =
        0xff946cf82975b1a2b6e6d28c9a76a4b8d7a1fd0592b785cb92771933310f9ee7;

    /**
     * @dev Load poseidon smart contract
     * @param _poseidon2Elements Poseidon contract address for 2 elements
     * @param _poseidon3Elements Poseidon contract address for 3 elements
     * @param _poseidon4Elements Poseidon contract address for 4 elements
     */
    function _initializeHelpers(
        address _poseidon2Elements,
        address _poseidon3Elements,
        address _poseidon4Elements
    ) internal onlyInitializing {
        _insPoseidonUnit2 = PoseidonUnit2(_poseidon2Elements);
        _insPoseidonUnit3 = PoseidonUnit3(_poseidon3Elements);
        _insPoseidonUnit4 = PoseidonUnit4(_poseidon4Elements);
    }
}