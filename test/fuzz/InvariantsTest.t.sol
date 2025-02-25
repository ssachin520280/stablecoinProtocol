// SPDX-License-Identifier: MIT

// This file will have our invariants i.e. properties that should always hold true 

// What are our invariants?
// 1. The total supply of the token should always be less than the total value of collateral
// 2. Getter view function should never return <- evergreen invariant

pragma solidity ^0.8.0;

import {DSCEngine} from '../../src/DSCEngine.sol';
import {DecentralizedStableCoin} from '../../src/DecentralizedStableCoin.sol';
import {DeployDSC} from '../../script/DeployDSC.s.sol';
import {HelperConfig} from '../../script/HelperConfig.s.sol';
import {Test} from 'forge-std/Test.sol';
import {console} from 'forge-std/console.sol';
import {StdInvariant} from 'forge-std/StdInvariant.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {Handler} from './Handler.t.sol';

contract InvariantsTest is StdInvariant, Test {
    DeployDSC deployer;
    DSCEngine dsce;
    DecentralizedStableCoin dsc;
    HelperConfig config;
    address weth;
    address wbtc;
    Handler handler;
    
    function setUp() external {
        console.log("abcd");
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
        (,, weth, wbtc,) = config.activeNetworkConfig();
        
        // Create and target the handler instead
        handler = new Handler(dsce, dsc);
        targetContract(address(handler));
        // targetContract(address(dsce));
    }

    function invariant_protocolMustHaveMoreValueThanTotalSupply() public view {
        uint256 totalSupply = dsc.totalSupply();
        uint256 totalWethDeplosited = IERC20(weth).balanceOf(address(dsce));
        uint256 totalWbtcDeplosited = IERC20(wbtc).balanceOf(address(dsce));

        uint256 wethValue = dsce.getUsdValue(weth, totalWethDeplosited);
        uint256 wbtcValue = dsce.getUsdValue(wbtc, totalWbtcDeplosited);
        console.log("Total Supply: ", totalSupply);
        console.log("Total Weth Value: ", wethValue);
        console.log("Total Wbtc Value: ", wbtcValue);
        console.log("times mint is called: ", handler.timesMintIsCalled());

        assert(totalSupply <= wethValue + wbtcValue);
    }

    function invariant_gettersShouldNeverRevert() public view {
        // dsce.getPrecision();
        // all the getters here
    }
}