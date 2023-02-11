// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./UNIMath.sol";

// aave v2
import "../interfaces/aave/ILendingPool.sol";
// aave v3
import "../interfaces/aave/V3/IPool.sol";
import "../interfaces/aave/V3/IProtocolDataProvider.sol";
import "../interfaces/aave/V3/IAtoken.sol";

// yearn
import {BaseStrategy,StrategyParams} from "@yearnvaults/contracts/BaseStrategy.sol";
import "../interfaces/yearn/IVault.sol";
import {IERC20, Address} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/Math.sol";

contract Strategy is BaseStrategy {
    using Address for address;

    // investment vault types:
    uint256 internal constant yearnVault = 0;
    uint256 internal constant aave2Vault = 2;
    uint256 internal constant aave3Vault = 3;

    uint32 internal priceInterval = 60 * 30;

    // aave v2 lending pool:
    ILendingPool private constant aave2pool = ILendingPool(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9);
    IProtocolDataProvider private constant aave2data = IProtocolDataProvider(0x057835Ad21a177dbdd3090bB1CAE03EaCF78Fc6d);

    // aave v3 lending pool:
    IPool private constant aave3pool = IPool(0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2);
    IProtocolDataProvider private constant aave3data = IProtocolDataProvider(0x7B4EB56E7CD4b454BA8ff71E4518426369a138a3);

    uint16 private constant aaveReferral = 7;

    uint256 public minWantLeftToAllocatePercentage = 0; //bps --> 100 = 1%
    uint256 public minWantLeftToLiquidatePercentage = 0; //bps --> 100 = 1%

    struct InvestmentVaultData {
        string vaultName;
        address vault;
        address vaultToken;
        address midToken;
        uint24 feeTokenToMid;
        uint24 feeMidToWant;
        uint24 vaultType;
        uint256 vaultTargetPercentAllocation;
    }

    //investment vaults
    InvestmentVaultData[] public investmentVault;
 
    constructor(address _mainVault) public BaseStrategy(_mainVault) {
    }

    // ******** OVERRIDE METHODS FROM BASE CONTRACT ************
    function name() external view override returns (string memory) {
        return "yieldfolio";
    }

    function estimatedTotalAssets() public view override returns (uint256) { 
        uint256 sumOfTotalAssets;
        uint256 lengthOfInvestmentVaults = investmentVault.length;
        for (uint256 i = 0; i < lengthOfInvestmentVaults; i++) {
            sumOfTotalAssets = sumOfTotalAssets.add(_vaultCurrentAssetsInWant(i));
        }
        return sumOfTotalAssets;
    }
    
    function vaultCurrentAssetsInWant(uint256 _index) external view returns (uint256){
        return _vaultCurrentAssetsInWant(_index);
    }

    function _vaultCurrentAssetsInWant(uint256 i) internal view returns (uint256){
        InvestmentVaultData memory currentInvestmentVault = investmentVault[i];
        uint256 ivaultCurrentAssetsInToken;
        if (currentInvestmentVault.vaultType == yearnVault) { //yearn
            ivaultCurrentAssetsInToken = _vaultCurrentAssetsInToken(currentInvestmentVault.vault);
        } else if (currentInvestmentVault.vaultType == aave2Vault || currentInvestmentVault.vaultType == aave3Vault) { //aavev2 OR aavev3
            ivaultCurrentAssetsInToken = IAToken(currentInvestmentVault.vault).balanceOf(address(this));
        }
        return UNIMath.oracleAmountOut(priceInterval, ivaultCurrentAssetsInToken, currentInvestmentVault.vaultToken, currentInvestmentVault.midToken, address(want), currentInvestmentVault.feeTokenToMid, currentInvestmentVault.feeMidToWant);
    }

    function _vaultCurrentAssetsInToken(address _investmentVault) internal view returns (uint256) {
        return IVault(_investmentVault).balanceOf(address(this)).mul(IVault(_investmentVault).pricePerShare()).div(10**IVault(_investmentVault).decimals());
    }

    function wantToVaultShares(uint256 _index, uint256 _wantAmount) external view returns (uint256){
        return _wantToVaultShares(_index, _wantAmount);
    }

    function _wantToVaultShares(uint256 i, uint256 _wantAmount) internal view returns (uint256){
        InvestmentVaultData memory currentInvestmentVault = investmentVault[i];
        uint256 amountInToken = UNIMath.oracleAmountOut(priceInterval, _wantAmount, address(want), currentInvestmentVault.midToken, currentInvestmentVault.vaultToken, currentInvestmentVault.feeMidToWant, currentInvestmentVault.feeTokenToMid);
        if (currentInvestmentVault.vaultType == yearnVault) { //yearn
            return _tokenToVaultShares(currentInvestmentVault.vault, amountInToken);
        } else if (currentInvestmentVault.vaultType == aave2Vault || currentInvestmentVault.vaultType == aave3Vault) { //aavev2 OR aavev3
            return amountInToken;
        }        
    }

    function _tokenToVaultShares(address _investmentVault, uint256 _tokenAmount) internal view returns (uint256) {
        return _tokenAmount.mul(10**IVault(_investmentVault).decimals()).div(IVault(_investmentVault).pricePerShare());
    }


    function prepareReturn(uint256 _debtOutstanding)
        internal
        override
        returns (
            uint256 _profit,
            uint256 _loss,
            uint256 _debtPayment
        )
    {
        uint256 totalDebt = IVault(address(vault)).totalDebt();
        uint256 totalAssetsAfterProfit = estimatedTotalAssets();
        _profit = totalAssetsAfterProfit > totalDebt
            ? totalAssetsAfterProfit.sub(totalDebt)
            : 0;

        uint256 _amountFreed;
        (_amountFreed, _loss) = liquidatePosition(_debtOutstanding.add(_profit));
        _debtPayment = Math.min(_debtOutstanding, _amountFreed);
        //Net profit and loss calculation
        if (_loss > _profit) {
            _loss = _loss.sub(_profit);
            _profit = 0;
        } else {
            _profit = _profit.sub(_loss);
            _loss = 0;
        }
    }
    function vaultCurrentPercentAllocation(uint256 i) external view returns (uint256){
        return _vaultCurrentPercentAllocation(i);
    }

    function _vaultCurrentPercentAllocation(uint256 i) internal view returns (uint256){
        uint256 mainVaultTotalAssets = IVault(address(vault)).totalAssets();
        if (mainVaultTotalAssets == 0){
            return 0;
        } 
        return _vaultCurrentAssetsInWant(i).mul(10000).div(mainVaultTotalAssets);
    }

    function vaultTargetPercentAllocation(uint256 i) external view returns (uint256){
        return investmentVault[i].vaultTargetPercentAllocation;
    }

    function vaultTargetAssetsInWant(uint256 i) external view returns (uint256){
        uint256 mainVaultTotalAssets = IVault(address(vault)).totalDebt();
        if (mainVaultTotalAssets == 0){
            mainVaultTotalAssets = estimatedTotalAssets();
            if (mainVaultTotalAssets == 0){
                return 0;
            } else {
                return mainVaultTotalAssets;
            }
        }
        return mainVaultTotalAssets.mul(investmentVault[i].vaultTargetPercentAllocation).div(10000);
    }

    function adjustPosition(uint256 _debtOutstanding) internal override {
        uint256 wantBalance = balanceOfWant();
        uint256 lengthOfInvestmentVaults = investmentVault.length;
        if (_debtOutstanding >= wantBalance || lengthOfInvestmentVaults == 0) {return;}
        uint256 wantLeftToAllocate = wantBalance.sub(_debtOutstanding);
        uint256 mainVaultTotalAssets = IVault(address(vault)).totalDebt();
        uint256 currentAssetsInWant;
        uint256 targetAssetsInWant;
        uint256[] memory vaultInvestmentInWant = new uint256[](lengthOfInvestmentVaults);
        uint256 percentualDivisionOfWantLeftToAllocate;
        //Goal: Loop through vaults and determine want amount from target allocation   
        for (uint i = 0; i < lengthOfInvestmentVaults; i++) {
            currentAssetsInWant = _vaultCurrentAssetsInWant(i);
            targetAssetsInWant = mainVaultTotalAssets.mul(investmentVault[i].vaultTargetPercentAllocation).div(100_00);
            if (targetAssetsInWant > currentAssetsInWant) {
                vaultInvestmentInWant[i] = targetAssetsInWant.sub(currentAssetsInWant);
                if (vaultInvestmentInWant[i] > wantLeftToAllocate) { 
                    vaultInvestmentInWant[i] = wantLeftToAllocate;
                    wantLeftToAllocate = 0;
                    break;
                }//in case there is no more want to allocate, everything is done & break loop!
                wantLeftToAllocate = wantLeftToAllocate.sub(vaultInvestmentInWant[i]);
            }
        }
        //if not enough investment left above a certain percentage threshold of main vault total assets is left, don't invest:
        if (wantLeftToAllocate <= mainVaultTotalAssets.mul(minWantLeftToAllocatePercentage).div(10000)) {
            wantLeftToAllocate = 0;
        }
        for (uint i = 1; i < lengthOfInvestmentVaults; i++) {
            percentualDivisionOfWantLeftToAllocate = wantLeftToAllocate.mul(investmentVault[i].vaultTargetPercentAllocation).div(100_00);
            vaultInvestmentInWant[i] = vaultInvestmentInWant[i].add(percentualDivisionOfWantLeftToAllocate);
            if (vaultInvestmentInWant[i] > mainVaultTotalAssets.mul(minWantLeftToAllocatePercentage).div(10000)) {
                //swap want to vaultToken & deposit in investmentVault
                if (investmentVault[i].vaultType == yearnVault) { //yearn
                    IVault(investmentVault[i].vault).deposit(UNIMath.swapKnownIn(vaultInvestmentInWant[i], address(want), investmentVault[i].midToken,  investmentVault[i].vaultToken,  investmentVault[i].feeMidToWant,  investmentVault[i].feeTokenToMid));
                } else if (investmentVault[i].vaultType == aave2Vault) { //aavev2
                    aave2pool.deposit(investmentVault[i].vaultToken, UNIMath.swapKnownIn(vaultInvestmentInWant[i], address(want), investmentVault[i].midToken,  investmentVault[i].vaultToken,  investmentVault[i].feeMidToWant,  investmentVault[i].feeTokenToMid), address(this), aaveReferral);
                } else if (investmentVault[i].vaultType == aave3Vault) { //aavev3
                    aave3pool.deposit(investmentVault[i].vaultToken, UNIMath.swapKnownIn(vaultInvestmentInWant[i], address(want), investmentVault[i].midToken,  investmentVault[i].vaultToken,  investmentVault[i].feeMidToWant,  investmentVault[i].feeTokenToMid), address(this), aaveReferral);
                }

            }
        }
        //special case for 0th vault --> deposit all the want left there
        wantBalance = balanceOfWant();
        if (wantBalance > _debtOutstanding) {
            IVault(investmentVault[0].vault).deposit(wantBalance.sub(_debtOutstanding));
        }
    }

    function liquidatePosition(uint256 _wantAmountNeeded)
        internal
        override
        returns (uint256 _liquidatedAmount, uint256 _loss)
    {
        uint256 wantBalance = balanceOfWant();
        if (_wantAmountNeeded > wantBalance){
            uint256 lengthOfInvestmentVaults = investmentVault.length;
            /////////////////////////////////////////////
            uint256 wantLeftToLiquidate = _wantAmountNeeded.sub(wantBalance);
            uint256 mainVaultTotalAssets = IVault(address(vault)).totalDebt();
            uint256 currentAssetsInWant;
            uint256 targetAssetsInWant;
            uint256[] memory vaultDivestmentInWant = new uint256[](lengthOfInvestmentVaults);
            uint256[] memory vaultDivestmentInToken = new uint256[](lengthOfInvestmentVaults);
            uint256 percentualDivisionOfWantLeftToLiquidate;
            //Goal: Loop through vaults and determine want amount from target allocation        
            for (uint i = 0; i < lengthOfInvestmentVaults; i++) {
                currentAssetsInWant = _vaultCurrentAssetsInWant(i);
                targetAssetsInWant = mainVaultTotalAssets.mul(investmentVault[i].vaultTargetPercentAllocation).div(10000);
                if (targetAssetsInWant < currentAssetsInWant) {
                    vaultDivestmentInWant[i] = currentAssetsInWant.sub(targetAssetsInWant);
                    if (vaultDivestmentInWant[i] > wantLeftToLiquidate) { 
                        vaultDivestmentInWant[i] = wantLeftToLiquidate;
                        wantLeftToLiquidate = 0;
                        break;
                    }//in case there is no more want to liquidate, everything is done & break loop!
                    wantLeftToLiquidate = wantLeftToLiquidate.sub(vaultDivestmentInWant[i]);
                }
            }
            //if not enough divestment left above a certain percentage of main vault total assets is left, don't divest:
            if (wantLeftToLiquidate <= mainVaultTotalAssets.mul(minWantLeftToLiquidatePercentage).div(10000)) {
                wantLeftToLiquidate = 0;
            }
            for (uint i = 0; i < lengthOfInvestmentVaults; i++) {
                //percentualDivisionOfWantLeftToLiquidate = wantLeftToLiquidate.mul(investmentVault[i].vaultTargetPercentAllocation).div(100_00);
                percentualDivisionOfWantLeftToLiquidate = wantLeftToLiquidate.mul(_vaultCurrentPercentAllocation(i)).div(100_00);
                vaultDivestmentInWant[i] = vaultDivestmentInWant[i].add(percentualDivisionOfWantLeftToLiquidate);
                if (vaultDivestmentInWant[i] > mainVaultTotalAssets.mul(minWantLeftToLiquidatePercentage).div(10000)) {
                    if (investmentVault[i].vaultType == yearnVault) { //yearn
                        UNIMath.swapKnownIn(IVault(investmentVault[i].vault).withdraw(Math.min(_wantToVaultShares(i, vaultDivestmentInWant[i]), IVault(investmentVault[i].vault).balanceOf(address(this)))), investmentVault[i].vaultToken, investmentVault[i].midToken, address(want), investmentVault[i].feeTokenToMid, investmentVault[i].feeMidToWant);
                    } else if (investmentVault[i].vaultType == aave2Vault) { //aavev2
                        UNIMath.swapKnownIn(aave2pool.withdraw(investmentVault[i].vaultToken, Math.min(_wantToVaultShares(i, vaultDivestmentInWant[i]), IVault(investmentVault[i].vault).balanceOf(address(this))), address(this)), investmentVault[i].vaultToken, investmentVault[i].midToken, address(want), investmentVault[i].feeTokenToMid, investmentVault[i].feeMidToWant);
                    } else if (investmentVault[i].vaultType == aave3Vault) { //aavev3
                        UNIMath.swapKnownIn(aave3pool.withdraw(investmentVault[i].vaultToken, Math.min(_wantToVaultShares(i, vaultDivestmentInWant[i]), IVault(investmentVault[i].vault).balanceOf(address(this))), address(this)), investmentVault[i].vaultToken, investmentVault[i].midToken, address(want), investmentVault[i].feeTokenToMid, investmentVault[i].feeMidToWant);
                    }
                }
            }
            //update free want after liquidating
            wantBalance = balanceOfWant();
            //loss calculation and returning liquidated amount
            if (_wantAmountNeeded > wantBalance) {
                _liquidatedAmount = wantBalance;
                _loss = _wantAmountNeeded.sub(wantBalance);
            } else {
                _liquidatedAmount = _wantAmountNeeded;
                _loss = 0;
            } 
            /////////////////////////////////////////////
        } else {
            _liquidatedAmount = _wantAmountNeeded;
        }
        
    }

    function liquidateAllPositions() internal override returns (uint256) {
    }

    function prepareMigration(address _newStrategy) internal override {
    }

    function protectedTokens() internal view override returns (address[] memory){}

    function ethToWant(uint _amtInWei) public view override returns (uint){return _amtInWei;}

    /////////////////// GETTERS:

    function balanceOfWant() internal view returns (uint256){
        return want.balanceOf(address(this));
    }


    ////////////////// SETTERS:
    function setPriceInterval(uint32 _priceInterval) external onlyGovernance {
        priceInterval = _priceInterval;
    }
/*
    function setMinWantLeftToAllocatePercentage(uint32 _minWantLeftToAllocatePercentage) external onlyGovernance {
        minWantLeftToAllocatePercentage = _minWantLeftToAllocatePercentage;
    }

    function setMinWantLeftToLiquidatePercentage(uint32 _minWantLeftToLiquidatePercentage) external onlyGovernance {
        minWantLeftToLiquidatePercentage = _minWantLeftToLiquidatePercentage;
    }
*/

    ///////////////////////// -----------------------DEPOSIT VAULT MECHANISM:
    
    //Add newInvestmentVault to investmentVault
    function addInvestmentVault(address _newInvestmentVault, address _vaultToken, address _midToken, uint24 _feeTokenToMid, uint24 _feeMidToWant, uint24 _vaultType, uint256 _vaultTargetPercentAllocation) public onlyGovernance {
        //Change data according to investment vault type:
        if (_vaultType == yearnVault) { //yearn
            IERC20(_vaultToken).approve(_newInvestmentVault, type(uint256).max);
        } else if (_vaultType == aave2Vault) { //aavev2
            IERC20(_vaultToken).approve(address(aave2pool), type(uint256).max);
            if (_newInvestmentVault == address(0)){
                (_newInvestmentVault, , ) = aave2data.getReserveTokensAddresses(_vaultToken);            
            }
        } else if (_vaultType == aave3Vault) { //aavev3
            IERC20(_vaultToken).approve(address(aave3pool), type(uint256).max);
            if (_newInvestmentVault == address(0)){
                (_newInvestmentVault, , ) = aave3data.getReserveTokensAddresses(_vaultToken);
            }
        }
        investmentVault.push(InvestmentVaultData(IVault(_newInvestmentVault).symbol(), _newInvestmentVault, _vaultToken, _midToken, _feeTokenToMid, _feeMidToWant, _vaultType, _vaultTargetPercentAllocation)); //Add
    }

    function setInvestmentVaultSwapSettings(uint256 _index, address _midToken, uint24 _feeTokenToMid, uint24 _feeMidToWant) public onlyGovernance {
        investmentVault[_index].midToken = _midToken;
        investmentVault[_index].feeTokenToMid = _feeTokenToMid;
        investmentVault[_index].feeMidToWant = _feeMidToWant;
    }

    function setInvestmentVaultTargetPercentAllocation(uint256 _index, uint256 _vaultTargetPercentAllocation) public onlyGovernance {
        investmentVault[_index].vaultTargetPercentAllocation = _vaultTargetPercentAllocation;
    }

    //Replace investmentVault at _index in investmentVault
    function replaceInvestmentVault(uint256 _index, address _newInvestmentVault, address _vaultToken, address _midToken, uint24 _feeTokenToMid, uint24 _feeMidToWant, uint24 _vaultType, uint256 _vaultTargetPercentAllocation) public onlyGovernance {
        //IERC20(investmentVault[_index].vaultToken).approve(investmentVault[_index].vault, 0);
        //IERC20(investmentVault[_index].vaultToken).approve(address(aave2pool), 0);
        //IERC20(investmentVault[_index].vaultToken).approve(address(aave3pool), 0);
        investmentVault[_index] = InvestmentVaultData(IVault(_newInvestmentVault).symbol(),_newInvestmentVault, _vaultToken, _midToken, _feeTokenToMid, _feeMidToWant, _vaultType, _vaultTargetPercentAllocation);
        IERC20(_vaultToken).approve(_newInvestmentVault, type(uint256).max);
        IERC20(_vaultToken).approve(address(aave2pool), type(uint256).max);
        IERC20(_vaultToken).approve(address(aave3pool), type(uint256).max);
    }

    //Remove investmentVault at _index in investmentVault
    function removeInvestmentVault(uint256 _index) public onlyGovernance {
        //IERC20(investmentVault[_index].vaultToken).approve(investmentVault[_index].vault, 0);
        //IERC20(investmentVault[_index].vaultToken).approve(address(aave2pool), 0);
        //IERC20(investmentVault[_index].vaultToken).approve(address(aave3pool), 0);
        uint256 lengthOfInvestmentVaults = investmentVault.length;
        for (uint256 i = _index; i < lengthOfInvestmentVaults.sub(1); i++) {
            investmentVault[i] = investmentVault[i + 1];
        }
        investmentVault.pop();
    }

}
