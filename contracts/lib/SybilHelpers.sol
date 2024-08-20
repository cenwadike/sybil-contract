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

    /**
     * @dev Decode half floating precision.
     * Max value encoded with this codification: 0x1f8def8800cca870c773f6eb4d980000000 (aprox 137 bits)
     * @param float Float half precision encode number
     * @return Decoded floating half precision
     */
    function _float2Fix(uint40 float) internal pure returns (uint256) {
        uint256 m = float & 0x7FFFFFFFF;
        uint256 e = float >> 35;

        // never overflow, max "e" value is 32
        uint256 exp = 10**e;

        // never overflow, max "fix" value is 1023 * 10^32
        uint256 fix = m * exp;

        return fix;
    }

    /**
     * @dev Copy 'len' bytes from memory address 'src', to address 'dest'.
     * From https://github.com/GNSPS/solidity-bytes-utils/blob/master/contracts/BytesLib.sol
     * @param _preBytes bytes storage
     * @param _postBytes Bytes array memory
     */
    function _concatStorage(bytes storage _preBytes, bytes memory _postBytes)
        internal
    {
        assembly {
            // Read the first 32 bytes of _preBytes storage, which is the length
            // of the array. (We don't need to use the offset into the slot
            // because arrays use the entire slot.)
            let fslot := sload(_preBytes.slot)
            // Arrays of 31 bytes or less have an even value in their slot,
            // while longer arrays have an odd value. The actual length is
            // the slot divided by two for odd values, and the lowest order
            // byte divided by two for even values.
            // If the slot is even, bitwise and the slot with 255 and divide by
            // two to get the length. If the slot is odd, bitwise and the slot
            // with -1 and divide by two.
            let slength := div(
                and(fslot, sub(mul(0x100, iszero(and(fslot, 1))), 1)),
                2
            )
            let mlength := mload(_postBytes)
            let newlength := add(slength, mlength)
            // slength can contain both the length and contents of the array
            // if length < 32 bytes so let's prepare for that
            // v. http://solidity.readthedocs.io/en/latest/miscellaneous.html#layout-of-state-variables-in-storage
            switch add(lt(slength, 32), lt(newlength, 32))
                case 2 {
                    // Since the new array still fits in the slot, we just need to
                    // update the contents of the slot.
                    // uint256(bytes_storage) = uint256(bytes_storage) + uint256(bytes_memory) + new_length
                    sstore(
                        _preBytes.slot,
                        // all the modifications to the slot are inside this
                        // next block
                        add(
                            // we can just add to the slot contents because the
                            // bytes we want to change are the LSBs
                            fslot,
                            add(
                                mul(
                                    div(
                                        // load the bytes from memory
                                        mload(add(_postBytes, 0x20)),
                                        // zero all bytes to the right
                                        exp(0x100, sub(32, mlength))
                                    ),
                                    // and now shift left the number of bytes to
                                    // leave space for the length in the slot
                                    exp(0x100, sub(32, newlength))
                                ),
                                // increase length by the double of the memory
                                // bytes length
                                mul(mlength, 2)
                            )
                        )
                    )
                }
                case 1 {
                    // The stored value fits in the slot, but the combined value
                    // will exceed it.
                    // get the keccak hash to get the contents of the array
                    mstore(0x0, _preBytes.slot)
                    let sc := add(keccak256(0x0, 0x20), div(slength, 32))

                    // save new length
                    sstore(_preBytes.slot, add(mul(newlength, 2), 1))

                    // The contents of the _postBytes array start 32 bytes into
                    // the structure. Our first read should obtain the `submod`
                    // bytes that can fit into the unused space in the last word
                    // of the stored array. To get this, we read 32 bytes starting
                    // from `submod`, so the data we read overlaps with the array
                    // contents by `submod` bytes. Masking the lowest-order
                    // `submod` bytes allows us to add that value directly to the
                    // stored value.

                    let submod := sub(32, slength)
                    let mc := add(_postBytes, submod)
                    let end := add(_postBytes, mlength)
                    let mask := sub(exp(0x100, submod), 1)

                    sstore(
                        sc,
                        add(
                            and(
                                fslot,
                                0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff00
                            ),
                            and(mload(mc), mask)
                        )
                    )

                    for {
                        mc := add(mc, 0x20)
                        sc := add(sc, 1)
                    } lt(mc, end) {
                        sc := add(sc, 1)
                        mc := add(mc, 0x20)
                    } {
                        sstore(sc, mload(mc))
                    }

                    mask := exp(0x100, sub(mc, end))

                    sstore(sc, mul(div(mload(mc), mask), mask))
                }
                default {
                    // get the keccak hash to get the contents of the array
                    mstore(0x0, _preBytes.slot)
                    // Start copying to the last used word of the stored array.
                    let sc := add(keccak256(0x0, 0x20), div(slength, 32))

                    // save new length
                    sstore(_preBytes.slot, add(mul(newlength, 2), 1))

                    // Copy over the first `submod` bytes of the new data as in
                    // case 1 above.
                    let slengthmod := mod(slength, 32)
                    let mlengthmod := mod(mlength, 32)
                    let submod := sub(32, slengthmod)
                    let mc := add(_postBytes, submod)
                    let end := add(_postBytes, mlength)
                    let mask := sub(exp(0x100, submod), 1)

                    sstore(sc, add(sload(sc), and(mload(mc), mask)))

                    for {
                        sc := add(sc, 1)
                        mc := add(mc, 0x20)
                    } lt(mc, end) {
                        sc := add(sc, 1)
                        mc := add(mc, 0x20)
                    } {
                        sstore(sc, mload(mc))
                    }

                    mask := exp(0x100, sub(mc, end))

                    sstore(sc, mul(div(mload(mc), mask), mask))
                }
        }
    }
}