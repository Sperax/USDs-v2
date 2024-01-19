// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {PreMigrationSetup} from ".././utils/DeploymentSetup.sol";
import {Dripper} from "../../contracts/rebase/Dripper.sol";
import {RebaseManager, Helpers} from "../../contracts/rebase/RebaseManager.sol";
import {IOracle} from "../../contracts/interfaces/IOracle.sol";
import {IERC20, ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {console} from "forge-std/console.sol";
import {IVault} from "../../contracts/interfaces/IVault.sol";
import {IUSDs} from "../../contracts/interfaces/IUSDs.sol";

contract RebaseManagerTest is PreMigrationSetup {
    //  Init Variables.
    Dripper public dripper;
    RebaseManager public rebaseManager;
    IVault internal vault;
    uint256 USDCePrecision;
    uint256 USDsPrecision;

    uint256 MAX_SUPPLY = ~uint128(0);

    // Events from the actual contract.
    event VaultUpdated(address vault);
    event DripperUpdated(address dripper);
    event GapUpdated(uint256 gap);
    event APRUpdated(uint256 aprBottom, uint256 aprCap);

    error CallerNotVault(address caller);
    error InvalidAPRConfig(uint256 aprBottom, uint256 aprCap);

    function setUp() public override {
        super.setUp();
        USDCePrecision = 10 ** ERC20(USDCe).decimals();
        USDsPrecision = 10 ** ERC20(USDS).decimals();
        vm.startPrank(USDS_OWNER);
        dripper = Dripper(DRIPPER);
        rebaseManager = RebaseManager(REBASE_MANAGER);
        vm.stopPrank();
    }

    function mintUSDs(uint256 amountIn) public {
        vm.startPrank(VAULT);
        IUSDs(USDS).mint(USDS_OWNER, amountIn);
        vm.stopPrank();
    }
}

contract Constructor is RebaseManagerTest {
    function test_Constructor() external {
        assertEq(rebaseManager.vault(), VAULT);
        assertEq(rebaseManager.dripper(), DRIPPER);
        assertEq(rebaseManager.gap(), REBASE_MANAGER_GAP);
        assertEq(rebaseManager.aprCap(), REBASE_MANAGER_APR_CAP);
        assertEq(rebaseManager.aprBottom(), REBASE_MANAGER_APR_BOTTOM);
        assertEq(rebaseManager.lastRebaseTS(), block.timestamp);
    }
}

contract UpdateVault is RebaseManagerTest {
    function test_RevertWhen_CallerIsNotOwner() external useActor(0) {
        address newVaultAddress = address(1);

        vm.expectRevert("Ownable: caller is not the owner");
        rebaseManager.updateVault(newVaultAddress);
    }

    function test_RevertWhen_InvalidAddress() external useKnownActor(USDS_OWNER) {
        address newVaultAddress = address(0);
        vm.expectRevert(abi.encodeWithSelector(Helpers.InvalidAddress.selector));
        rebaseManager.updateVault(newVaultAddress);
    }

    function test_UpdateVault(address newVaultAddress) external useKnownActor(USDS_OWNER) {
        vm.assume(newVaultAddress != address(0));

        vm.expectEmit(address(rebaseManager));
        emit VaultUpdated(newVaultAddress);
        rebaseManager.updateVault(newVaultAddress);

        assertEq(rebaseManager.vault(), newVaultAddress);
    }
}

contract UpdateDripper is RebaseManagerTest {
    function test_RevertWhen_CallerIsNotOwner() external useActor(0) {
        address newDripperAddress = address(1);

        vm.expectRevert("Ownable: caller is not the owner");
        rebaseManager.updateDripper(newDripperAddress);
    }

    function test_RevertWhen_InvalidAddress() external useKnownActor(USDS_OWNER) {
        address newDripperAddress = address(0);
        vm.expectRevert(abi.encodeWithSelector(Helpers.InvalidAddress.selector));
        rebaseManager.updateDripper(newDripperAddress);
    }

    function test_UpdateDripper(address newDripperAddress) external useKnownActor(USDS_OWNER) {
        vm.assume(newDripperAddress != address(0));

        vm.expectEmit(address(rebaseManager));
        emit DripperUpdated(newDripperAddress);
        rebaseManager.updateDripper(newDripperAddress);

        assertEq(rebaseManager.dripper(), newDripperAddress);
    }
}

contract UpdateGap is RebaseManagerTest {
    function test_RevertWhen_CallerIsNotOwner() external useActor(0) {
        vm.expectRevert("Ownable: caller is not the owner");
        rebaseManager.updateGap(7 days);
    }

    function test_UpdateGap(uint256 gap) external useKnownActor(USDS_OWNER) {
        vm.expectEmit(address(rebaseManager));
        emit GapUpdated(gap);
        rebaseManager.updateGap(gap);

        assertEq(rebaseManager.gap(), gap);
    }
}

contract UpdateAPR is RebaseManagerTest {
    function test_RevertWhen_InvalidAPRConfig() external useKnownActor(USDS_OWNER) {
        uint256 aprBottom = 10;
        uint256 aprCap = 9;

        vm.expectRevert(abi.encodeWithSelector(InvalidAPRConfig.selector, aprBottom, aprCap));
        rebaseManager.updateAPR(aprBottom, aprCap);
    }

    function test_RevertWhen_CallerIsNotOwner() external useActor(0) {
        uint256 aprBottom = 10;
        uint256 aprCap = 9;

        vm.expectRevert("Ownable: caller is not the owner");
        rebaseManager.updateAPR(aprBottom, aprCap);
    }

    function test_UpdateAPR(uint256 aprBottom, uint256 aprCap) external useKnownActor(USDS_OWNER) {
        vm.assume(aprBottom <= aprCap);

        vm.expectEmit(address(rebaseManager));
        emit APRUpdated(aprBottom, aprCap);
        rebaseManager.updateAPR(aprBottom, aprCap);

        assertEq(rebaseManager.aprBottom(), aprBottom);
        assertEq(rebaseManager.aprCap(), aprCap);
    }
}

contract FetchRebaseAmt is RebaseManagerTest {
    event Collected(uint256 amount);

    function test_RevertWhen_CallerNotVault() external useActor(0) {
        vm.expectRevert(abi.encodeWithSelector(CallerNotVault.selector, actors[0]));
        rebaseManager.fetchRebaseAmt();
    }

    function test_FetchRebaseAmt_WhenRebaseAmtIsZero() external useKnownActor(VAULT) {
        uint256 rebaseAmt = rebaseManager.fetchRebaseAmt();
        assertEq(rebaseAmt, 0);
    }

    function test_FetchRebaseAmt(uint256 _amount, uint256 vaultBalance) external useKnownActor(VAULT) {
        _amount = bound(_amount, 7 days, MAX_SUPPLY - IUSDs(USDS).totalSupply());
        vaultBalance = bound(vaultBalance, 1, MAX_SUPPLY - IUSDs(USDS).totalSupply());
        uint256 calculatedRebaseAmt = _amount + vaultBalance;
        vm.mockCall(address(USDS), abi.encodeWithSignature("balanceOf(address)", VAULT), abi.encode(vaultBalance));

        mintUSDs(_amount);
        changePrank(USDS_OWNER);
        IERC20(USDS).approve(address(dripper), _amount);
        dripper.addUSDs(_amount);

        changePrank(VAULT);
        skip(14 days); // to collect all the drip
        uint256 lastRebaseTS = rebaseManager.lastRebaseTS();
        skip(rebaseManager.gap()); // to allow rebase

        (uint256 minRebaseAmt, uint256 maxRebaseAmt) = rebaseManager.getMinAndMaxRebaseAmt();
        assert(minRebaseAmt > 0);
        assert(maxRebaseAmt > 0);

        uint256 availableRebaseAmt = rebaseManager.getAvailableRebaseAmt();
        assertEq(availableRebaseAmt, calculatedRebaseAmt);

        if (calculatedRebaseAmt < minRebaseAmt) {
            uint256 rebaseAmt = rebaseManager.fetchRebaseAmt();

            assertEq(rebaseAmt, 0);
            assertEq(rebaseManager.lastRebaseTS(), lastRebaseTS);
        } else {
            vm.expectEmit(address(dripper));
            emit Collected(_amount);
            uint256 rebaseAmt = rebaseManager.fetchRebaseAmt();

            assertEq(rebaseManager.lastRebaseTS(), block.timestamp);

            if (calculatedRebaseAmt > maxRebaseAmt) {
                assertEq(rebaseAmt, maxRebaseAmt);
            } else {
                assertEq(rebaseAmt, calculatedRebaseAmt);
            }
        }
    }

    // TODO remove this?
    function test_FetchRebaseAmt_Scenario() external {
        vm.prank(VAULT);
        rebaseManager.fetchRebaseAmt();
        // current price feed data of USDCe
        IOracle.PriceData memory usdceData = IOracle(ORACLE).getPrice(USDS);
        uint256 usdcePrice = usdceData.price;
        uint256 usdcePrecision = usdceData.precision;
        skip(10 days);
        // Using mock call to set price feed as we are skipping 10 days into the future and oracle will not have the data for that day.
        vm.mockCall(
            address(ORACLE), abi.encodeWithSignature("getPrice(address)", USDCe), abi.encode(usdcePrice, usdcePrecision)
        );
        // Minting USDs
        mintUSDs(1e11);
        vm.prank(USDS_OWNER);
        IERC20(USDS).transfer(address(dripper), 1e11);

        vm.startPrank(VAULT);
        dripper.collect();
        console.log("Day 1 After Minting USDs");
        skip(1 days);
        (uint256 min, uint256 max) = rebaseManager.getMinAndMaxRebaseAmt();
        console.log("Min Rebase Amt", min / (10 ** 18), "max Rebase Amt", max / (10 ** 18));
        uint256 collectable0 = dripper.getCollectableAmt();
        console.log("collectable0", collectable0 / 10 ** 18);
        skip(1 days);
        console.log("Day 2 After Minting USDs");
        (uint256 min2, uint256 max2) = rebaseManager.getMinAndMaxRebaseAmt();
        console.log("Min Rebase Amt", min2 / (10 ** 18), "max Rebase Amt", max2 / (10 ** 18));
        uint256 collectable = dripper.getCollectableAmt();
        console.log("collectable1", collectable / 10 ** 18);
        uint256 rebaseAmt1 = rebaseManager.fetchRebaseAmt();
        console.log("Rebase Amount", rebaseAmt1 / 10 ** 18);
        // Trying to collect from dripper after rebase
        dripper.collect();
        skip(1 days);
        console.log("Day 3 After Minting USDs");
        (uint256 min3, uint256 max3) = rebaseManager.getMinAndMaxRebaseAmt();
        console.log("Min Rebase Amt", min3 / (10 ** 18), "max Rebase Amt", max3 / (10 ** 18));
        uint256 collectable3 = dripper.getCollectableAmt();
        console.log("collectable3", collectable3 / 10 ** 18);
        uint256 rebaseAmt3 = rebaseManager.fetchRebaseAmt();
        console.log("Rebase Amount", rebaseAmt3 / 10 ** 18);
    }
}
