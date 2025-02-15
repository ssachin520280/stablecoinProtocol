// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title DecentralizedStableCoin (DSC)
 * @author Sachin Anand
 * @notice This is an ERC20 implementation of a decentralized stablecoin
 * @dev This contract is controlled by the DSCEngine. No direct user interaction.
 *
 * Collateral System:
 * - Type: Exogenous (backed by assets outside the protocol - wETH & wBTC)
 * - Ratio: To be defined in DSCEngine
 * 
 * Stability Mechanism:
 * - Minting: Algorithmic, based on collateral value
 * - Pegged to: USD (1 DSC = 1 USD)
 * - Stability: Maintained through overcollateralization
 *
 * Security Considerations:
 * - This contract must be owned and controlled only by the DSCEngine
 * - Direct user interactions should be prevented
 * - All minting/burning should follow strict collateral requirements
 */
contract DecentralizedStableCoin is ERC20Burnable, Ownable {
    error DecentralizedStableCoin__MustBeMoreThanZero();
    error DecentralizedStableCoin__BurnAmountExceedsBalance();

    constructor() ERC20("DecentalizedStableCoin", "DSC") Ownable(msg.sender) {}

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (_amount <= 0) {
            revert DecentralizedStableCoin__MustBeMoreThanZero();
        }
        if (balance < _amount) {
            revert DecentralizedStableCoin__BurnAmountExceedsBalance();
        }
        super.burn(_amount);
    }

}