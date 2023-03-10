// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

interface IVault is IERC20 {
    function token() external view returns (address);
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint256);

    //function deposit() external;
    function deposit(uint256) external;

    function depositAll() external;

    function pricePerShare() external view returns (uint256);

    function withdraw() external returns (uint256);

    function withdraw(uint256 amount) external returns (uint256);

    function withdraw(
        uint256 amount,
        address account,
        uint256 maxLoss
    ) external returns (uint256);

    function availableDepositLimit() external view returns (uint256);

    function totalAssets() external view returns (uint256);
    function totalDebt() external view returns (uint256);
}
