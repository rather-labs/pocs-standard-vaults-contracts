// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.17;

import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {LendingBaseVault} from "../../layer-1-vaults/lending/base/LendingBaseVault.sol";
import {IUniswapV2Router02} from "../../interfaces/IUniswapV2Router02.sol";

import {ERC4626Factory} from "../../base/ERC4626Factory.sol";
import {VaultParams, IDeltaNeutralVault} from "./IDeltaNeutralVault.sol";

/// @title DeltaNeutralVault
/// @author ffarall, LucaCevasco
/// @notice Automated delta neutral DeFi strategy that uses a lending vault and a
/// staking vault implementing an ERC4626 interface and which also implements the ERC4626
/// standard for its use.
/// @dev Supplies the base asset (a stablecoin) to the lending vault, uses it as collateral,
/// and then borrows against it to invest in the staking vault
contract DeltaNeutralVault is Ownable, Initializable, ERC4626, IDeltaNeutralVault {
    using SafeERC20 for ERC20;
    using Math for uint256;

    /// -----------------------------------------------------------------------
    /// Immutable params
    /// -----------------------------------------------------------------------

    /// @notice Underlying asset of this vault, and that which is supplied as collateral
    /// to the lending vault.
    ERC20 public lendingAsset;
    /// @notice Asset borrowed from the lending vault, and that which is supplied to
    /// the staking vault.
    ERC20 public stakingAsset;
    /// @notice Lending vault used for providing collateral and borrowing against it
    ERC4626 public lendingVault;
    /// @notice Staking vault in which this vault invests what borrows from the lending vault
    ERC4626 public stakingVault;
    /// @notice The ratio between the value of the asset borrowed and the asset lent,
    /// in percentage terms with one decimal (for 75.5%, borrowRate = 755).
    uint256 public borrowRate;

    /// -----------------------------------------------------------------------
    /// Constructor
    /// -----------------------------------------------------------------------

    constructor()
    ERC4626(IERC20(address(0)))
    ERC20("DeltaNeutralVault", "DNV") { }

    /// -----------------------------------------------------------------------
    /// Initializable
    /// -----------------------------------------------------------------------

    function initialize(
        VaultParams memory lendingVaultParams,
        VaultParams memory stakingVaultParams,
        address deployer
    ) external initializer {
        _transferOwnership(deployer);

        lendingAsset = lendingVaultParams.asset;
        stakingAsset = stakingVaultParams.asset;
        ERC4626Factory lendingVaultFactory = lendingVaultParams.factory;
        ERC4626Factory stakingVaultFactory = stakingVaultParams.factory;

        // Get lending vault from factories
        if (lendingVaultFactory.vaultExists(lendingAsset, lendingVaultParams.data)) {
            lendingVault = lendingVaultFactory.computeERC4626Address(lendingAsset, lendingVaultParams.data);
        } else {
            lendingVault = lendingVaultFactory.createERC4626(lendingAsset, lendingVaultParams.data);
        }

        // Get satking vault from factories
        if (stakingVaultFactory.vaultExists(stakingAsset, stakingVaultParams.data)) {
            stakingVault = stakingVaultFactory.computeERC4626Address(stakingAsset, stakingVaultParams.data);
        } else {
            stakingVault = stakingVaultFactory.createERC4626(stakingAsset, stakingVaultParams.data);
        }

        // ERC20 authorisations
        lendingAsset.safeApprove(address(lendingVault), 2**256 - 1);
        stakingAsset.safeApprove(address(lendingVault), 2**256 - 1);
        stakingAsset.safeApprove(address(stakingVault), 2**256 - 1);
    }

    /// -----------------------------------------------------------------------
    /// ERC4626 overrides
    /// -----------------------------------------------------------------------

    /// @inheritdoc ERC4626
    function asset() public view virtual override returns (address) {
        return address(lendingAsset);
    }

    /// @inheritdoc ERC4626
    function totalAssets() public view virtual override returns (uint256) {
        uint256 lendingVaultShares = lendingVault.balanceOf(address(this));
        return _convertToAssets(lendingVaultShares, Math.Rounding.Down);
    }

    /// @inheritdoc ERC4626
    function _deposit(
        address caller, 
        address receiver, 
        uint256 assets, 
        uint256 shares
    ) internal virtual override {
        // If _asset is ERC777, `transferFrom` can trigger a reenterancy BEFORE the transfer happens through the
        // `tokensToSend` hook. On the other hand, the `tokenReceived` hook, that is triggered after the transfer,
        // calls the vault, which is assumed not malicious.
        //
        // Conclusion: we need to do the transfer before we mint so that any reentrancy would happen before the
        // assets are transferred and before the shares are minted, which is a valid state.
        // slither-disable-next-line reentrancy-no-eth
        SafeERC20.safeTransferFrom(ERC20(asset()), caller, address(this), assets);

        // Deposit in lending vault
        lendingVault.deposit(assets, address(this));

        // Deposit in staking vault all that was borrowed from the lending vault
        uint256 amountAssetStake = stakingAsset.balanceOf(address(this));
        stakingVault.deposit(amountAssetStake, address(this));

        _mint(receiver, shares);

        emit Deposit(caller, receiver, assets, shares);
    }

    /// @inheritdoc ERC4626
    function _withdraw(
        address caller, 
        address receiver, 
        address owner, 
        uint256 assets, 
        uint256 shares
    ) internal virtual override {
        // If _asset is ERC777, `transfer` can trigger a reentrancy AFTER the transfer happens through the
        // `tokensReceived` hook. On the other hand, the `tokensToSend` hook, that is triggered before the transfer,
        // calls the vault, which is assumed not malicious.
        //
        // Conclusion: we need to do the transfer after the burn so that any reentrancy would happen after the
        // shares are burned and after the assets are transferred, which is a valid state.
        _burn(owner, shares);

        // Withdraw from staking vault
        uint256 stakingShares = stakingVault.balanceOf(address(this)); // TODO * balanceOf(owner) / totalSupply();
        stakingVault.redeem(stakingShares, address(this), address(this));

        // Withdraw from lending vault
        uint256 lendingShares = lendingVault.balanceOf(address(this)); // TODO * balanceOf(owner) / totalSupply();
        lendingVault.redeem(lendingShares, address(this), address(this));

        // Transfering leftover tokens from staking investment
        uint256 amountStakingAssets = stakingAsset.balanceOf(address(this));
        stakingAsset.safeTransfer(receiver, amountStakingAssets);

        ERC20(asset()).safeTransfer(receiver, assets);

        emit Withdraw(caller, receiver, owner, assets, shares);
    }

    /// @inheritdoc ERC4626
    function _convertToShares(uint256 assets, Math.Rounding) internal view virtual override returns (uint256) {
        // TODO this is an oversimplified estimation
        return lendingVault.convertToShares(assets);
    }

    /// @inheritdoc ERC4626
    function _convertToAssets(uint256 shares, Math.Rounding) internal view virtual override returns (uint256) {
        // TODO this is an oversimiplified estimation
        return lendingVault.convertToAssets(shares);
    }
}