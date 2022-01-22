// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "./ERC20.sol";
import "./Ownable.sol";
import "./libraries/SafeMath.sol";
import "./interfaces/IPinkAntiBot.sol";
import "./interfaces/IUniswapV2Factory.sol";
import "./interfaces/IUniswapV2Router02.sol";

contract MicroPets is ERC20, Ownable {
    using SafeMath for uint256;

    IPinkAntiBot public pinkAntiBot;
    IUniswapV2Router02 public uniswapV2Router;
    address public  uniswapV2Pair;

    bool private swapping;

    address public deadWallet = 0x000000000000000000000000000000000000dEaD;

    mapping(address => bool) private _liquidityHolders;
    mapping(address => bool) private _isSniper;

    uint256 public buyTax = 3;
    uint256 public sellTax = 12;
    uint256 public liquidityFee = 2;
    uint256 public buybackFee = 10;
    uint256 public bonusSellTax = 30;
    uint256 public bonusBuyTax = 0;
    uint256 public _cooldownSeconds = 3600;
    uint256 public _cooldownBuyFee = 1;
    uint256 public _cooldownSellFee = 20;
    uint256 public totalFees = (liquidityFee).add(buybackFee);
    address payable public _buybackWalletAddress;
    address payable public _buybackWalletAddress2;
    address public currentLiqPair;

    uint256 public launchedAt = 0;
    uint256 public swapAndLiquifycount = 0;
    uint256 public snipersCaught = 0;
    uint256 public lastblocknumber = 0;
    uint256 public bonusBlockTime = 1;
    uint256 public cooldownBlockTime = 1;
    uint256 public lastPairBalance = 0;
    uint256 public blockchunk = 5;
    uint256 public _startTimeForSwap;
    uint256 public _intervalSecondsForSwap = 30 * 1 seconds;
    uint256 public divgas = 30000;
    uint256 public buybackDivisor = 30;
    bool private sniperProtection = true;
    bool public _hasLiqBeenAdded = false;
    bool public checkUptrendActive = false;
    bool public multiBuybackWallet = false;
    bool public pinkAntiBotEnabled = false;

    uint256 public bottimer = 3;

    uint256 public minimumTokensBeforeSwap = 1000000000 * (10 ** 18);
    uint256 public _maxTxAmount = 10000000000 * (10 ** 18);
    uint256 public _maxWallet = 100000000000 * (10 ** 18);

    // exlcude from fees and max transaction amount
    mapping(address => bool) private _isExcludedFromFees;


    // store addresses that a automatic market maker pairs. Any transfer *to* these addresses
    // could be subject to a maximum transfer amount
    mapping(address => bool) public automatedMarketMakerPairs;

    event UpdateUniswapV2Router(address indexed newAddress, address indexed oldAddress);

    event ExcludeFromFees(address indexed account, bool isExcluded);
    event ExcludeMultipleAccountsFromFees(address[] accounts, bool isExcluded);

    event SetAutomatedMarketMakerPair(address indexed pair, bool indexed value);

    event LiquidityWalletUpdated(address indexed newLiquidityWallet, address indexed oldLiquidityWallet);

    event GasForProcessingUpdated(uint256 indexed newValue, uint256 indexed oldValue);

    event SwapandLiquify(
        uint256 tokensSwapped,
        uint256 ethReceived,
        uint256 tokensIntoLiqudity
    );

    constructor(address _initiationAddress, address _initiationBuyback, address pinkAntiBot_) public ERC20("MicroPets", "PETS") {
        _buybackWalletAddress = payable(_initiationBuyback);

        // Pinksale Pancake Router Testnet v1
        // IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(0xD99D1c33F9fC3444f8101754aBC46c52416550D1);

        // Pancake Router Testnet v1
        // IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3);

        // Pancakeswap Router Mainnet v2
        IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(0x10ED43C718714eb63d5aA57B78B54704E256024E);

        // Create a uniswap pair for this new token
        address _uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory())
            .createPair(address(this), _uniswapV2Router.WETH());

        pinkAntiBot = IPinkAntiBot(pinkAntiBot_);
        pinkAntiBot.setTokenOwner(msg.sender);

        uniswapV2Router = _uniswapV2Router;
        uniswapV2Pair = _uniswapV2Pair;
        currentLiqPair = _uniswapV2Pair;

        _setAutomatedMarketMakerPair(_uniswapV2Pair, true);

        _liquidityHolders[_initiationAddress] = true;
        // exclude from paying fees or having max transaction amount
        excludeFromFees(_initiationAddress, true);
        excludeFromFees(address(this), true);
        _startTimeForSwap = block.timestamp;
        lastblocknumber = block.number;

        /*
            _mint is an internal function in ERC20.sol that is only called here,
            and CANNOT be called ever again
        */
        _mint(_initiationAddress, 10000000000000 * (10 ** 18));
        transferOwnership(_initiationAddress);
    }

    receive() external payable {
    }

    function updateUniswapV2Router(address newAddress) public onlyOwner {
        require(newAddress != address(uniswapV2Router), "MicroPets: The router already has that address");
        emit UpdateUniswapV2Router(newAddress, address(uniswapV2Router));
        uniswapV2Router = IUniswapV2Router02(newAddress);
        address _uniswapV2Pair = IUniswapV2Factory(uniswapV2Router.factory())
        .createPair(address(this), uniswapV2Router.WETH());
        uniswapV2Pair = _uniswapV2Pair;
    }

    function excludeFromFees(address account, bool excluded) public onlyOwner {
        require(_isExcludedFromFees[account] != excluded, "MicroPets: Account is already the value of 'excluded'");
        _isExcludedFromFees[account] = excluded;

        emit ExcludeFromFees(account, excluded);
    }

    function excludeMultipleAccountsFromFees(address[] calldata accounts, bool excluded) public onlyOwner {
        for (uint256 i = 0; i < accounts.length; i++) {
            _isExcludedFromFees[accounts[i]] = excluded;
        }

        emit ExcludeMultipleAccountsFromFees(accounts, excluded);
    }

    function setBuybackWallet(address payable wallet) external onlyOwner {
        _buybackWalletAddress = wallet;
    }


    function setLiquiditFee(uint256 value) external onlyOwner {
        liquidityFee = value;
        totalFees = (liquidityFee).add(buybackFee);
    }

    function setBuybackFee(uint256 value) external onlyOwner {
        buybackFee = value;
        totalFees = (liquidityFee).add(buybackFee);
    }

    function setAutomatedMarketMakerPair(address pair, bool value) public onlyOwner {
        require(pair != uniswapV2Pair, "MicroPets: The PancakeSwap pair cannot be removed from automatedMarketMakerPairs");

        _setAutomatedMarketMakerPair(pair, value);
    }


    function _setAutomatedMarketMakerPair(address pair, bool value) private {
        require(automatedMarketMakerPairs[pair] != value, "MicroPets: Automated market maker pair is already set to that value");
        automatedMarketMakerPairs[pair] = value;

        if (value) {
        }

        emit SetAutomatedMarketMakerPair(pair, value);
    }

    function isExcludedFromFees(address account) public view returns (bool) {
        return _isExcludedFromFees[account];
    }

    function setBuybackAddress(address _buybackAddress1, address _buybackAddress2) external onlyOwner {
        _buybackWalletAddress = payable(_buybackAddress1);
        _buybackWalletAddress2 = payable(_buybackAddress2);
    }

    function setBonusSellTax(uint256 _buy, uint256 _sell) external onlyOwner {
        bonusSellTax = _sell;
        bonusBuyTax = _buy;
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        if (pinkAntiBotEnabled) {
            pinkAntiBot.onPreTransferCheck(from, to, amount);
        }

        if (!_isExcludedFromFees[from] && !_isExcludedFromFees[to]) {
            require(amount <= _maxTxAmount, "Transfer amount exceeds the maxTxAmount.");
            if (to != uniswapV2Pair) {
                require(balanceOf(to).add(amount) <= _maxWallet, "Transfer exceeds max");
            }
        }

        if (sniperProtection) {
            // if sender is a sniper address, reject the sell.
            if (isSniper(from)) {
                revert('Sniper rejected.');
            }

            // check if this is the liquidity adding tx to startup.
            if (!_hasLiqBeenAdded) {
                _checkLiquidityAdd(from, to);
            } else {
                if (
                    launchedAt > 0
                    && from == uniswapV2Pair
                    && !_liquidityHolders[from]
                && !_liquidityHolders[to]
                ) {
                    if (block.number - launchedAt < bottimer) {
                        _isSniper[to] = true;
                        snipersCaught++;
                    }
                }
            }
        }

        if (amount == 0) {
            super._transfer(from, to, 0);
            return;
        }

        uint256 contractTokenBalance = balanceOf(address(this));

        bool canSwap = contractTokenBalance >= minimumTokensBeforeSwap;

        bool uptrendEstablished;

        if (checkUptrendActive) {
            uptrendEstablished = checkUptrend();
        } else {
            uptrendEstablished = true;
        }

        if (lastblocknumber.add(blockchunk) < block.number && launched()) {
            lastblocknumber = block.number;
            lastPairBalance = balanceOf(currentLiqPair);
        }

        if (canSwap &&
            !swapping &&
            !automatedMarketMakerPairs[from] &&
            from != owner() &&
            to != owner()
        ) {
            if (uptrendEstablished && _startTimeForSwap + _intervalSecondsForSwap <= block.timestamp) {
                _startTimeForSwap = block.timestamp;
                swapAndLiquifycount = swapAndLiquifycount.add(1);
                swapping = true;

                SwapAndLiquify(minimumTokensBeforeSwap);

                swapping = false;
            }
        }

        bool takeFee = !swapping;

        // if any account belongs to _isExcludedFromFee account then remove the fee
        if (_isExcludedFromFees[from] || _isExcludedFromFees[to]) {
            takeFee = false;
        }

        uint256 fees;
        if (takeFee) {
            if (to == uniswapV2Pair) {
                if (sellTax > 0) {
                    if (block.timestamp < bonusBlockTime) {
                        fees = amount.mul(bonusSellTax).div(100);
                        amount = amount.sub(fees);
                        super._transfer(from, address(this), fees);
                    } else if (block.timestamp < cooldownBlockTime) {
                        fees = amount.mul(_cooldownSellFee).div(100);
                        amount = amount.sub(fees);
                        super._transfer(from, address(this), fees);
                    } else {
                        fees = amount.mul(sellTax).div(100);
                        amount = amount.sub(fees);
                        super._transfer(from, address(this), fees);
                    }
                }
            } else {
                if (buyTax > 0) {
                    if (block.timestamp < bonusBlockTime) {
                        if (bonusBuyTax > 0) {
                            fees = amount.mul(bonusBuyTax).div(100);
                            amount = amount.sub(fees);
                            super._transfer(from, address(this), fees);
                        }
                    } else if (block.timestamp < cooldownBlockTime) {
                        fees = amount.mul(_cooldownBuyFee).div(100);
                        amount = amount.sub(fees);
                        super._transfer(from, address(this), fees);
                    } else {
                        fees = amount.mul(buyTax).div(100);
                        amount = amount.sub(fees);
                        super._transfer(from, address(this), fees);
                    }
                }
            }
        }

        super._transfer(from, to, amount);
    }

    function swapTokensForEth(uint256 tokenAmount) private {
        // generate the uniswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();

        _approve(address(this), address(uniswapV2Router), tokenAmount);

        // make the swap
        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            address(this),
            block.timestamp
        );
    }

    function manualSwapnLiq() public onlyOwner {
        _startTimeForSwap = block.timestamp;
        swapAndLiquifycount = swapAndLiquifycount.add(1);
        swapping = true;
        SwapAndLiquify(minimumTokensBeforeSwap);
        swapping = false;
    }

    function addLiquidity(uint256 tokenAmount, uint256 ethAmount) private {
        // approve token transfer to cover all possible scenarios
        _approve(address(this), address(uniswapV2Router), tokenAmount);

        // add the liquidity
        uniswapV2Router.addLiquidityETH{value : ethAmount}(
            address(this),
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            owner(),
            block.timestamp
        );
    }

    function SwapAndLiquify(uint256 tokens) private {
        uint256 tokensforLiq = 0;
        if (liquidityFee == 0) {
            tokensforLiq = 0;
        } else {
            tokensforLiq = tokens.mul(liquidityFee).div(totalFees);
        }
        uint256 tokensforBuyback = 0;
        if (buybackFee == 0) {
            tokensforBuyback = 0;
        } else {
            tokensforBuyback = tokens.mul(buybackFee).div(totalFees);
        }

        uint256 half = 0;
        if (tokensforLiq != 0) {
            half = tokensforLiq.div(2);
        }

        uint256 initialBalance = address(this).balance;
        swapTokensForEth(tokensforBuyback.add(half));

        uint256 transferredBalance = address(this).balance.sub(initialBalance);

        uint256 otherHalf = tokensforLiq.sub(half);

        // capture the contract's current ETH balance.
        // this is so that we can capture exactly the amount of ETH that the
        // swap creates, and not make the liquidity event include any ETH that
        // has been manually sent to the contract

        // add liquidity to uniswap
        uint256 bnbForLiq = 0;
        if (tokensforLiq != 0) {
            bnbForLiq = transferredBalance.mul(liquidityFee).div(liquidityFee.add(buybackFee));
            addLiquidity(otherHalf, bnbForLiq);
        }

        emit SwapandLiquify(half, bnbForLiq, otherHalf);
        uint256 buybackBalance = address(this).balance;
        if (buybackBalance > 0) {
            if (multiBuybackWallet) {
                uint256 bal1 = buybackBalance.mul(buybackDivisor).div(100);
                uint256 bal2 = buybackBalance.sub(bal1);
                payable(_buybackWalletAddress).call{value : bal1, gas : divgas}("");
                payable(_buybackWalletAddress2).call{value : bal2, gas : divgas}("");
            } else {
                payable(_buybackWalletAddress).call{value : buybackBalance, gas : divgas}("");
            }

        }
    }

    function transferContractToken(address _token, address _to, uint256 _quant) public onlyOwner returns (bool _sent){
        _sent = IERC20(_token).transfer(_to, _quant);
    }

    function setBuySellTax(uint256 _buyTax, uint256 _sellTax) external onlyOwner {
        buyTax = _buyTax;
        sellTax = _sellTax;
    }

    function setBonusTime(uint256 _seconds) external onlyOwner {
        bonusBlockTime = block.timestamp.add(_seconds);
        cooldownBlockTime = bonusBlockTime.add(_cooldownSeconds);
    }

    function changeSnipe(bool _snipe) external onlyOwner {
        sniperProtection = _snipe;
    }

    function Sweep() external onlyOwner {
        uint256 balance = address(this).balance;
        payable(owner()).transfer(balance);
    }

    function GetSwapMinutes() public view returns (uint256) {
        return _intervalSecondsForSwap.div(60);
    }

    function SetSwapSeconds(uint256 newSeconds) external onlyOwner {
        _intervalSecondsForSwap = newSeconds * 1 seconds;
    }

    function checkUptrend() public view returns (bool) {
        if (lastblocknumber.add(blockchunk) < block.number) {
            if (balanceOf(currentLiqPair) < lastPairBalance) {
                return true;
            }
        }
        return false;
    }

    function setEnableAntiBot(bool _enable) external onlyOwner {
        pinkAntiBotEnabled = _enable;
    }

    function setLastBlockNumber(uint256 _number) public onlyOwner {
        lastblocknumber = _number;
    }

    function setLastPairBalance() public onlyOwner {
        lastPairBalance = balanceOf(currentLiqPair);
    }

    function setminimumTokensBeforeSwap(uint256 _new) public onlyOwner {
        minimumTokensBeforeSwap = _new;
    }

    function changeDivgas(uint256 _new) public onlyOwner {
        divgas = _new;
    }

    function setBlockChunk(uint256 _chunk) external onlyOwner {
        blockchunk = _chunk;
    }

    function setCurrentLiqPair(address _pair) public onlyOwner {
        currentLiqPair = _pair;
    }

    function botTimer(uint256 _timer) public onlyOwner {
        bottimer = _timer;
    }

    function launched() internal view returns (bool) {
        return launchedAt != 0;
    }

    function setMaxTxAmount(uint256 maxTxAmount) external onlyOwner {
        require(maxTxAmount > totalSupply().div(10000), "max tx too low");
        _maxTxAmount = maxTxAmount;
    }

    function setcheckUptrendActive(bool _enabled) public onlyOwner {
        checkUptrendActive = _enabled;
    }

    function setMultiBuybackWallet(bool _enabled) public onlyOwner {
        multiBuybackWallet = _enabled;
    }

    function _checkLiquidityAdd(address from, address to) private {
        // if liquidity is added by the _liquidityholders set trading enables to true and start the anti sniper timer
        require(!_hasLiqBeenAdded, 'Liquidity already added and marked.');
        if (_liquidityHolders[from] && to == uniswapV2Pair) {
            _hasLiqBeenAdded = true;
            launchedAt = block.number;
        }
    }

    function setBuybackDivisor(uint256 _divisor) external onlyOwner {
        buybackDivisor = _divisor;
    }

    function isSniper(address account) public view returns (bool) {
        return _isSniper[account];
    }

    function removeSniper(address account) external onlyOwner {
        require(_isSniper[account], 'Account is not a recorded sniper.');
        _isSniper[account] = false;
    }

    function changeMaxWallet(uint256 maxWallet) external onlyOwner {
        require(maxWallet > totalSupply().div(10000), "max wallet too low");
        _maxWallet = maxWallet;
    }

    function coolDownSettings(uint256 cooldownSeconds, uint256 cooldownBuyFee, uint256 cooldownSellFee) external onlyOwner {
        _cooldownSeconds = cooldownSeconds;
        _cooldownBuyFee = cooldownBuyFee;
        _cooldownSellFee = cooldownSellFee;
    }

    function launch() public onlyOwner {
        launchedAt = block.number;
        _hasLiqBeenAdded = true;
    }

    function setDxSaleAddress(address dxRouter, address presaleRouter) external onlyOwner {
        _liquidityHolders[dxRouter] = true;
        _isExcludedFromFees[dxRouter] = true;
        _liquidityHolders[presaleRouter] = true;
        _isExcludedFromFees[presaleRouter] = true;
    }

    function multisend(address[] memory dests, uint256[] memory values) public onlyOwner returns (uint256) {
        uint256 i = 0;
        while (i < dests.length) {
            super._transfer(msg.sender, dests[i], values[i]);
            i += 1;
        }
        return (i);
    }

    function addLiquidityHolderSolo(address holder, bool _choice) external onlyOwner {
        _liquidityHolders[holder] = _choice;
    }

    function addLiquidityHolder(address holder) external onlyOwner {
        _liquidityHolders[holder] = true;
        excludeFromFees(holder, true);
    }
}