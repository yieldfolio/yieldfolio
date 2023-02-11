import pytest
from brownie import config
from brownie import Contract


@pytest.fixture
def gov(accounts):
    yield accounts.at("0xFEB4acf3df3cDEA7399794D0869ef76A6EfAff52", force=True)


@pytest.fixture
def user(accounts):
    yield accounts[0]


@pytest.fixture
def rewards(accounts):
    yield accounts[1]


@pytest.fixture
def guardian(accounts):
    yield accounts[2]


@pytest.fixture
def management(accounts):
    yield accounts[3]


@pytest.fixture
def strategist(accounts):
    yield accounts[4]


@pytest.fixture
def keeper(accounts):
    yield accounts[5]


@pytest.fixture
def token():
    token_address = "0x6B175474E89094C44Da98b954EedeAC495271d0F"  # DAI
    yield Contract(token_address)

@pytest.fixture
def token_whale(accounts):
    yield accounts.at("0xF977814e90dA44bFA03b6295A0616a897441aceC", force=True) #Reserve = Binance8

@pytest.fixture
def weth_whale(accounts):
    yield accounts.at("0x57757E3D981446D585Af0D9Ae4d7DF6D64647806", force=True)

@pytest.fixture
def yvdai(accounts):
    yield Contract("0xdA816459F1AB5631232FE5e97a05BBBb94970c95")

@pytest.fixture
def yvuni(accounts):
    yield Contract("0xFBEB78a723b8087fD2ea7Ef1afEc93d35E8Bed42")

@pytest.fixture
def uni(accounts):
    yield Contract("0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984")

@pytest.fixture
def dai(accounts, yvdai):
    yield Contract(yvdai.token())

@pytest.fixture
def yvusdc(accounts):
    yield Contract("0xa354F35829Ae975e850e23e9615b11Da1B3dC4DE")

@pytest.fixture
def yvusdt(accounts):
    yield Contract("0x3B27F92C0e212C671EA351827EDF93DB27cc0c65")

@pytest.fixture
def usdc(accounts, yvusdc):
    yield Contract(yvusdc.token())

@pytest.fixture
def yvweth(accounts):
    yield Contract("0xa258C4606Ca8206D8aA700cE2143D7db854D168c")

@pytest.fixture
def chainlink_weth(accounts):
    yield Contract("0x5f4ec3df9cbd43714fe2740f5e3616155c5b8419")

@pytest.fixture
def chainlink_wbtc(accounts):
    yield Contract("0xf4030086522a5beea4988f8ca5b36dbc97bee88c")

@pytest.fixture
def chainlink_usdc(accounts):
    yield Contract("0x8fffffd4afb6115b954bd326cbe7b4ba576818f6")

@pytest.fixture
def chainlink_uni(accounts):
    yield Contract("0x553303d460ee0afb37edff9be42922d8ff63220e")

@pytest.fixture
def yvwbtc(accounts):
    yield Contract("0xA696a63cc78DfFa1a63E9E50587C197387FF6C7E")

@pytest.fixture
def wbtc(accounts, yvwbtc):
    yield Contract(yvwbtc.token())

@pytest.fixture
def token_whale(accounts):
    yield accounts.at("0xF977814e90dA44bFA03b6295A0616a897441aceC", force=True) #Reserve = Binance8

@pytest.fixture
def amount(accounts, token, user, token_whale):
    amount = 10_000 * 10 ** token.decimals()
    # In order to get some funds for the token you are about to use,
    # it impersonate an exchange address to use it's funds.
    reserve = token_whale
    token.transfer(user, amount, {"from": reserve})
    yield amount


@pytest.fixture
def weth():
    token_address = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"
    yield Contract(token_address)


@pytest.fixture
def weth_amout(user, weth):
    weth_amout = 10 ** weth.decimals()
    user.transfer(weth, weth_amout)
    yield weth_amout


@pytest.fixture
def vault(pm, gov, rewards, guardian, management, token):
    Vault = pm(config["dependencies"][0]).Vault
    vault = guardian.deploy(Vault)
    vault.initialize(token, gov, rewards, "", "", guardian, management)
    vault.setDepositLimit(2 ** 256 - 1, {"from": gov})
    vault.setManagement(management, {"from": gov})
    yield vault

@pytest.fixture(autouse=True)
def lib(gov, UNIMath):
    yield UNIMath.deploy({"from": gov})

@pytest.fixture
def strategy(strategist, keeper, vault, Strategy, gov):
    strategy = strategist.deploy(Strategy, vault)
    strategy.setKeeper(keeper)
    vault.addStrategy(strategy, 10_000, 0, 2 ** 256 - 1, 1_000, {"from": gov})
    yield strategy


@pytest.fixture(scope="session")
def RELATIVE_APPROX():
    yield 1e-5

@pytest.fixture(scope="session")
def RELATIVE_APPROX2():
    yield 1e-2
