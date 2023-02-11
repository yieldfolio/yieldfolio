// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.6.12;
pragma experimental ABIEncoderV2;
//pragma abicoder v2;

interface IERC20Decimals {
    function decimals() external view returns (uint8);
}
