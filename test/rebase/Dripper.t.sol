// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {BaseTest} from ".././utils/BaseTest.sol";
import {Dripper, Helpers} from "../../contracts/rebase/Dripper.sol";
import {IUSDs} from "../../contracts/interfaces/IUSDs.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

address constant WHALE_USDS = 0x50450351517117Cb58189edBa6bbaD6284D45902;

contract DripperTest is BaseTest {
    //  Constants for the test.
    uint256 constant DRIP_DURATION = 7 days;
    uint256 MAX_SUPPLY = ~uint128(0);

    //  Init Variables.
    Dripper public dripper;

    // Events from external contracts
    event Transfer(address indexed from, address indexed to, uint256 value);

    // Events from the actual contract.
    event Collected(uint256 amount);
    event VaultUpdated(address vault);
    event DripDurationUpdated(uint256 dripDuration);
    event Recovered(address owner, uint256 amount);

    error NothingToRecover();

    function setUp() public override {
        super.setUp();
        setArbitrumFork();
        dripper = new Dripper(VAULT, DRIP_DURATION);
        dripper.transferOwnership(USDS_OWNER);
    }
}

contract TestConstructor is DripperTest {
    function test_Constructor() external {
        assertEq(dripper.vault(), VAULT);
        assertEq(dripper.dripDuration(), DRIP_DURATION);
        assertEq(dripper.lastCollectTS(), block.timestamp);
    }
}

contract UpdateVault is DripperTest {
    function test_RevertWhen_CallerIsNotOwner() external useActor(0) {
        address newVaultAddress = address(1);

        vm.expectRevert("Ownable: caller is not the owner");
        dripper.updateVault(newVaultAddress);
    }

    function test_RevertWhen_VaultIsZeroAddress() external useKnownActor(USDS_OWNER) {
        address newVaultAddress = address(0);
        vm.expectRevert(abi.encodeWithSelector(Helpers.InvalidAddress.selector));
        dripper.updateVault(newVaultAddress);
    }

    function testFuzz_UpdateVault(address newVaultAddress) external useKnownActor(USDS_OWNER) {
        vm.assume(newVaultAddress != address(0));

        vm.expectEmit(address(dripper));
        emit VaultUpdated(newVaultAddress);
        dripper.updateVault(newVaultAddress);

        assertEq(dripper.vault(), newVaultAddress);
    }
}

contract UpdateDripDuration is DripperTest {
    function test_RevertWhen_CallerIsNotOwner() external useActor(0) {
        vm.expectRevert("Ownable: caller is not the owner");
        dripper.updateDripDuration(0);
    }

    function test_RevertWhen_InvalidInput() external useKnownActor(USDS_OWNER) {
        vm.expectRevert(abi.encodeWithSelector(Helpers.InvalidAmount.selector));
        dripper.updateDripDuration(0);
    }

    function testFuzz_UpdateDripDuration(uint256 dripDuration) external useKnownActor(USDS_OWNER) {
        vm.assume(dripDuration != 0);

        vm.expectEmit(address(dripper));
        emit DripDurationUpdated(dripDuration);
        dripper.updateDripDuration(dripDuration);

        assertEq(dripper.dripDuration(), dripDuration);
    }
}

contract RecoverTokens is DripperTest {
    function test_RevertWhen_CallerIsNotOwner() external useActor(0) {
        vm.expectRevert("Ownable: caller is not the owner");
        dripper.recoverTokens(USDCe);
    }

    function test_RevertWhen_NothingToRecover() external useKnownActor(USDS_OWNER) {
        vm.expectRevert(abi.encodeWithSelector(NothingToRecover.selector));
        dripper.recoverTokens(USDCe);
    }

    function testFuzz_RecoverTokens(uint128 amount) external useKnownActor(USDS_OWNER) {
        address[4] memory assets = [USDCe, USDT, FRAX, DAI];
        vm.assume(amount != 0);
        for (uint8 i = 0; i < assets.length; i++) {
            deal(address(assets[i]), address(dripper), amount, true);
            vm.expectEmit(address(assets[i]));
            emit Transfer(address(dripper), USDS_OWNER, amount);
            vm.expectEmit(address(dripper));
            emit Recovered(USDS_OWNER, amount);
            dripper.recoverTokens((assets[i]));
        }
    }
}

contract Collect is DripperTest {
    function test_Collect_ZeroBalance() external useActor(0) {
        assertEq(dripper.getCollectableAmt(), 0);
        uint256 collectableAmt = dripper.collect();
        assertEq(collectableAmt, 0);
    }

    function testFuzz_CollectDripper(uint256 _amount) external {
        _amount = bound(_amount, 1, MAX_SUPPLY - IUSDs(USDS).totalSupply());

        changePrank(VAULT);
        IUSDs(USDS).mint(WHALE_USDS, _amount);
        changePrank(WHALE_USDS);
        IERC20(USDS).approve(address(dripper), _amount);
        dripper.addUSDs(_amount);
        skip(8 days); // adding one additional day so that full amount can be collected

        vm.expectEmit(address(USDS));
        emit Transfer(address(dripper), VAULT, _amount);
        vm.expectEmit(address(dripper));
        emit Collected(_amount);
        uint256 collectableAmt = dripper.collect();

        assertEq(collectableAmt, _amount);
    }
}

contract AddUSDs is DripperTest {
    function test_RevertWhen_InvalidInput() external useActor(0) {
        vm.expectRevert(abi.encodeWithSelector(Helpers.InvalidAmount.selector));
        dripper.addUSDs(0);
    }

    function testFuzz_AddUSDs(uint256 _amount) external {
        _amount = bound(_amount, 1, MAX_SUPPLY - IUSDs(USDS).totalSupply());

        changePrank(VAULT);
        IUSDs(USDS).mint(WHALE_USDS, _amount);
        changePrank(WHALE_USDS);
        IERC20(USDS).approve(address(dripper), _amount);

        vm.expectEmit(USDS);
        emit Transfer(WHALE_USDS, address(dripper), _amount);
        dripper.addUSDs(_amount);

        assertEq(dripper.dripRate(), _amount / DRIP_DURATION);
    }
}
