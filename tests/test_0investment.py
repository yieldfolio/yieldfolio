import brownie
from brownie import Contract, ZERO_ADDRESS
import pytest


def test_investment(
    chain, accounts, token, vault, strategy, user, amount, RELATIVE_APPROX2, yvdai, yvusdc, yvweth, yvwbtc, dai, usdc, weth, weth_whale, wbtc, gov, token_whale, yvusdt, yvuni, uni, chainlink_weth, chainlink_wbtc, chainlink_usdc, chainlink_uni
):

    strategy.addInvestmentVault(yvdai, dai, dai, 100, 100, 0, 1000, {"from": gov})
    strategy.addInvestmentVault(ZERO_ADDRESS, usdc, usdc, 100, 100, 2, 1000, {"from": gov})
    strategy.addInvestmentVault(ZERO_ADDRESS, weth, weth, 500, 500, 3, 4000, {"from": gov}) #weth, usdc, 500, 100
    strategy.addInvestmentVault(yvwbtc, wbtc, usdc, 3000, 100, 0, 4000, {"from": gov}) #should also work with yvwbtc, wbtc, usdc, 500, 100, 4000
    #strategy.addInvestmentVault(yvuni, uni, weth, 3000, 500, 0, {"from": gov})

    #Deposit
    deposit_amount = 10*1e18
    token.approve(vault, 2**256-1,{"from": token_whale})
    vault.deposit(deposit_amount, {"from": token_whale})
    assert vault.totalAssets() == deposit_amount
    # harvest
    chain.sleep(1)
    strategy.harvest({"from": gov})

    #Deposit
    deposit_amount2 = 90*1e18
    token.approve(vault, 2**256-1,{"from": token_whale})
    vault.deposit(deposit_amount2, {"from": token_whale})
    # harvest
    chain.sleep(1)
    strategy.harvest({"from": gov})    

    assert pytest.approx(strategy.estimatedTotalAssets(), rel=RELATIVE_APPROX2) == deposit_amount + deposit_amount2

    strategy.addInvestmentVault(yvuni, uni, weth, 3000, 500, 0, 0, {"from": gov})
    vault.updateStrategyDebtRatio(strategy, 0, {"from": gov})
    strategy.harvest({"from": gov})

    assert strategy.vaultCurrentPercentAllocation(4) < 1e18
    assert strategy.estimatedTotalAssets() < 1e18

    vault.updateStrategyDebtRatio(strategy, 100_00, {"from": gov})
    strategy.harvest({"from": gov})

    assert pytest.approx(strategy.estimatedTotalAssets(), rel=RELATIVE_APPROX2) == deposit_amount + deposit_amount2
    assert strategy.vaultCurrentPercentAllocation(4) < 1e18
    assert pytest.approx(strategy.vaultCurrentAssetsInWant(4), rel=RELATIVE_APPROX2)  == 0

    #test percentages:
    vault.updateStrategyDebtRatio(strategy, 90_00, {"from": gov})
    strategy.setInvestmentVaultTargetPercentAllocation(0, 20_00, {"from": gov})
    strategy.setInvestmentVaultTargetPercentAllocation(1, 20_00, {"from": gov})
    strategy.setInvestmentVaultTargetPercentAllocation(2, 20_00, {"from": gov})
    strategy.setInvestmentVaultTargetPercentAllocation(3, 20_00, {"from": gov})
    strategy.setInvestmentVaultTargetPercentAllocation(4, 20_00, {"from": gov})
