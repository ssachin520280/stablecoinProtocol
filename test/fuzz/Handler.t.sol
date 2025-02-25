// SPDX-License-Identifier: MIT
// Handler is going to narrow down the way we call functions. This way we won't be wasting fuzz rounds trivially.

import {Test, console} from 'forge-std/Test.sol';
import {DSCEngine} from '../../src/DSCEngine.sol';
import {DecentralizedStableCoin} from '../../src/DecentralizedStableCoin.sol';
import {ERC20Mock} from '@openzeppelin/contracts/mocks/token/ERC20Mock.sol';

contract Handler is Test {
    DSCEngine dsce;
    DecentralizedStableCoin dsc;
    ERC20Mock weth;
    ERC20Mock wbtc;
    uint256 MAX_DEPOSIT_SIZE = type(uint96).max;

    constructor(DSCEngine _dsce, DecentralizedStableCoin _dsc) {
        dsce = _dsce;
        dsc = _dsc;

        address[] memory collateralTokens = dsce.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);
    }

    function depositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);
        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amountCollateral);
        collateral.approve(address(dsce), amountCollateral);
        dsce.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
    }

    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        uint256 maxCollateralToRedeem = dsce.getCollateralBalanceOfUser(address(collateral), msg.sender);
        console.log("maxCollateralToRedeem", maxCollateralToRedeem);
        console.log("max uint96", type(uint96).max);
        vm.startPrank(msg.sender);
        uint256 upperBound = maxCollateralToRedeem < MAX_DEPOSIT_SIZE ? maxCollateralToRedeem : MAX_DEPOSIT_SIZE;
        amountCollateral = bound(amountCollateral, 0, upperBound);
        console.log("amountCollateral", amountCollateral);
        if(amountCollateral == 0) {
            vm.stopPrank();
            return;
        }
        dsce.redeemCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
    }

    // Helper functions

    function _getCollateralFromSeed(uint256 collateralSeed) private view returns (ERC20Mock) {
        return collateralSeed % 2 == 0 ? weth : wbtc;
    }
}