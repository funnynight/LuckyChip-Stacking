// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

interface ILuckyChipReferral {
    /**
     * @dev Record referrer.
     */
    function recordReferrer(address user, address referrer) external;

    /**
     * @dev Record lp referral commission.
     */
    function recordLpCommission(address referrer, uint256 commission) external;

    /**
     * @dev Record banker referral commission.
     */
    function recordBankerCommission(address referrer, uint256 commission) external;

    /**
     * @dev Record player referral commission.
     */
    function recordPlayerCommission(address referrer, uint256 commission) external;

    /**
     * @dev Get the referrer address that referred the user.
     */
    function getReferrer(address user) external view returns (address);

    /**
     * @dev Get the commission referred by the user. (lpCommission, bankerCommission, playerCommission)
     */
    function getReferralCommission(address user) external view returns (uint256, uint256, uint256);

    /**
     * @dev Get the lucky power of user.
     */
    function getPower(address user) external view returns (uint256);

    /**
     * @dev claim all LC.
     */
    function claim() external;

}
