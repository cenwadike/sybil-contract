// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.6.12;

import "./SybilHelpers.sol";

contract InstantWithdrawManager is SybilHelpers {

    // Number of buckets
    uint256 private constant _MAX_BUCKETS = 5;

    // Bucket array
    uint256 public nBuckets;
    mapping (int256 => uint256) public buckets;

    // Withdraw delay in seconds
    uint64 public withdrawalDelay;

    // ERC20 decimals signature
    //  bytes4(keccak256(bytes("decimals()")))
    bytes4 private constant _ERC20_DECIMALS = 0x313ce567;

    uint256 private constant _MAX_WITHDRAWAL_DELAY = 2 weeks;

    // Mapping tokenAddress --> (USD value)/token , default 0, means that token does not worth
    // 2^64 = 1.8446744e+19
    // fixed point codification is used, 9 digits for integer part, 10 digits for decimal
    // In other words, the USD value of a token base unit is multiplied by 1e10
    // MaxUSD value for a base unit token: 1844674407,3709551616$
    // MinUSD value for a base unit token: 1e-10$
    mapping(address => uint64) public tokenExchange;

    uint256 private constant _EXCHANGE_MULTIPLIER = 1e10;

    event UpdateBucketWithdraw(
        uint256 indexed numBucket,
        uint256 indexed blockStamp,
        uint256 withdrawals
    );

    event UpdateWithdrawalDelay(uint64 newWithdrawalDelay);
    event UpdateBucketsParameters(uint256[] arrayBuckets);
    event UpdateTokenExchange(address[] addressArray, uint64[] valueArray);
    event SafeMode();

    function _initializeWithdraw(
        uint64 _withdrawalDelay
    ) internal initializer {
        withdrawalDelay = _withdrawalDelay;
    }

    /**
     * @dev Attempt to use instant withdraw
     * @param amount Amount to withdraw
     */
    function _processInstantWithdrawal(address tokenAddress, uint192 amount)
        internal
        returns (bool)
    {
        // find amount in USD and then the corresponding bucketIdx
        uint256 amountUSD = _token2USD(tokenAddress, amount);

        if (amountUSD == 0) {
            return true;
        }

        int256 bucketIdx = _findBucketIdx(amountUSD);
        if (bucketIdx == -1) return true;

        (uint256 ceilUSD, uint256 blockStamp, uint256 withdrawals, uint256 rateBlocks, uint256 rateWithdrawals, uint256 maxWithdrawals) = unpackBucket(buckets[bucketIdx]);

        // update the bucket and check again if are withdrawals available
        uint256 differenceBlocks = block.number - blockStamp;
        uint256 periods = differenceBlocks/rateBlocks;

        // add the withdrawals available
        withdrawals = withdrawals + (periods * rateWithdrawals);
        if (withdrawals >= maxWithdrawals) {
            withdrawals = maxWithdrawals;
            blockStamp = block.number;
        } else {
            blockStamp = blockStamp + (periods * rateBlocks);
        }

        if (withdrawals == 0) return false;

        withdrawals = withdrawals - 1;

        // update the bucket with the new values
        buckets[bucketIdx] = packBucket(ceilUSD, blockStamp, withdrawals, rateBlocks, rateWithdrawals, maxWithdrawals);

        emit UpdateBucketWithdraw(uint(bucketIdx), blockStamp, withdrawals);
        return true;
    }

     /**
     * @dev Converts tokens to USD
     * @param tokenAddress Token address
     * @param amount Token amount
     * @return Total USD amount
     */
    function _token2USD(address tokenAddress, uint192 amount)
        internal
        view
        returns (uint256)
    {
        if (tokenExchange[tokenAddress] == 0) return 0;

        // this multiplication never overflows 192bits * 64 bits
        uint256 baseUnitTokenUSD = (uint256(amount) *
            uint256(tokenExchange[tokenAddress])) / _EXCHANGE_MULTIPLIER;

        uint8 decimals;
        // in case of ether, set 18 decimals
        if (tokenAddress == address(0)) {
            decimals = 18;
        } else {
            // if decimals() is not implemented 0 decimals are assumed
            (bool success, bytes memory data) = tokenAddress.staticcall(
                abi.encodeWithSelector(_ERC20_DECIMALS)
            );
            if (success) {
                decimals = abi.decode(data, (uint8));
            }
        }
        require(
            decimals < 77,
            "InstantWithdrawManager::_token2USD: TOKEN_DECIMALS_OVERFLOW"
        );
        return baseUnitTokenUSD / (10**uint256(decimals));
    }

    /**
     * @dev Find the corresponding bucket for the input amount
     * @param amountUSD USD amount
     * @return Bucket index, -1 in case there is no match
     */
    function _findBucketIdx(uint256 amountUSD) internal view returns (int256) {
        for (int256 i = 0; i < int256(nBuckets); i++) {
            uint256 ceilUSD = buckets[i] & 0xFFFFFFFF_FFFFFFFF_FFFFFFFF;
            if ((amountUSD <= ceilUSD) ||
                (ceilUSD == 0xFFFFFFFF_FFFFFFFF_FFFFFFFF))
            {
                return i;
            }
        }
        return -1;
    }

    /**
     * @dev Unpack a packed uint256 into the bucket parameters
     * @param bucket Token address
     * @return ceilUSD max USD value that bucket holds
     * @return blockStamp block number of the last bucket update
     * @return withdrawals available withdrawals of the bucket
     * @return rateBlocks every `rateBlocks` blocks add `rateWithdrawals` withdrawal
     * @return rateWithdrawals add `rateWithdrawals` every `rateBlocks`
     * @return maxWithdrawals max withdrawals the bucket can hold
     */
    function unpackBucket(uint256 bucket) public pure returns(
        uint256 ceilUSD,
        uint256 blockStamp,
        uint256 withdrawals,
        uint256 rateBlocks,
        uint256 rateWithdrawals,
        uint256 maxWithdrawals
    ) {
        ceilUSD = bucket & 0xFFFFFFFF_FFFFFFFF_FFFFFFFF;
        blockStamp = (bucket >> 96) & 0xFFFFFFFF;
        withdrawals = (bucket >> 128) & 0xFFFFFFFF;
        rateBlocks = (bucket >> 160) & 0xFFFFFFFF;
        rateWithdrawals = (bucket >> 192) & 0xFFFFFFFF;
        maxWithdrawals = (bucket >> 224) & 0xFFFFFFFF;
    }

    /**
     * @dev Pack all the bucket parameters into a uint256
     * @param ceilUSD max USD value that bucket holds
     * @param blockStamp block number of the last bucket update
     * @param withdrawals available withdrawals of the bucket
     * @param rateBlocks every `rateBlocks` blocks add `rateWithdrawals` withdrawal
     * @param rateWithdrawals add `rateWithdrawals` every `rateBlocks`
     * @param maxWithdrawals max withdrawals the bucket can hold
     * @return ret all bucket varaibles packed [ceilUSD, blockStamp, withdrawals, rateBlocks, rateWithdrawals, maxWithdrawals]
     */
    function packBucket(
        uint256 ceilUSD,
        uint256 blockStamp,
        uint256 withdrawals,
        uint256 rateBlocks,
        uint256 rateWithdrawals,
        uint256 maxWithdrawals
    ) public pure returns(uint256 ret) {
        ret = ceilUSD |
              (blockStamp << 96) |
              (withdrawals << 128) |
              (rateBlocks << 160) |
              (rateWithdrawals << 192) |
              (maxWithdrawals << 224);
    }
}