/**
 *Submitted for verification at BscScan.com on 2021-02-28
*/

pragma solidity ^0.5.10;

library SafeMath {
    function mul(uint256 a, uint256 b) internal pure returns (uint256 c) {
      if (a == 0) {
        return 0;
      }
      c = a * b;
      assert(c / a == b);
      return c;
    }

    function div(uint256 a, uint256 b) internal pure returns (uint256) {
      return a / b;
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
      assert(b <= a);
      return a - b;
    }

    function add(uint256 a, uint256 b) internal pure returns (uint256 c) {
      c = a + b;
      assert(c >= a);
      return c;
    }
}

contract TOKEN {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
}

contract Ownable {
    address public owner;

    constructor() public {
      owner = address(0xF4210B747e44592035da0126f70C48Cb04634Eac);
    }

    modifier onlyOwner() {
      require(msg.sender == owner);
      _;
    }
}

contract LPFarm is Ownable {
    using SafeMath for uint256;

    uint256 ACTIVATION_TIME = 1614555600;

    modifier isActivated {
        require(now >= ACTIVATION_TIME);
        _;
    }

    modifier hasDripped {
        if (dividendPool > 0) {
          uint256 secondsPassed = SafeMath.sub(now, lastDripTime);
          uint256 dividends = secondsPassed.mul(dividendPool).div(dailyRate);

          if (dividends > dividendPool) {
            dividends = dividendPool;
          }

          profitPerShare = SafeMath.add(profitPerShare, (dividends * divMagnitude) / tokenSupply);
          dividendPool = dividendPool.sub(dividends);
          lastDripTime = now;
        }
        _;
    }

    modifier onlyTokenHolders {
        require(myTokens() > 0);
        _;
    }

    modifier onlyDivis {
        require(myDividends() > 0);
        _;
    }

    event onDonation(
        address indexed customerAddress,
        uint256 tokens
    );

    event Transfer(
        address indexed from,
        address indexed to,
        uint256 tokens
    );

    event onTokenPurchase(
        address indexed customerAddress,
        uint256 incomingTokens,
        uint256 tokensMinted,
        uint256 timestamp
    );

    event onTokenSell(
        address indexed customerAddress,
        uint256 tokensBurned,
        uint256 tronEarned,
        uint256 timestamp
    );

    event onRoll(
        address indexed customerAddress,
        uint256 tronRolled,
        uint256 tokensMinted
    );

    event onWithdraw(
        address indexed customerAddress,
        uint256 tronWithdrawn
    );

    string public name = "Toad LP Farm";
    string public symbol = "TLPF";
    uint8 constant public decimals = 18;
    uint256 constant private divMagnitude = 2 ** 64;

    uint32 constant private dailyRate = 8640000; //1% a day
    uint8 constant private buyInFee = 9;
    uint8 constant private sellOutFee = 9;
    uint8 constant private burnFee = 1;

    mapping(address => uint256) private tokenBalanceLedger;
    mapping(address => int256) private payoutsTo;

    struct Stats {
       uint256 deposits;
       uint256 withdrawals;
    }

    mapping(address => Stats) public playerStats;

    uint256 public dividendPool = 0;
    uint256 public lastDripTime = ACTIVATION_TIME;
    uint256 public totalPlayer = 0;
    uint256 public totalDonation = 0;
    uint256 public totalBurnFundReceived = 0;
    uint256 public totalBurnFundCollected = 0;

    uint256 private tokenSupply = 0;
    uint256 private profitPerShare = 0;

    address public burnAddress;
    TOKEN bep20;

    constructor() public {
        burnAddress = address(0xdEaD); //burning address
        bep20 = TOKEN(address(0x20A3DC9C2ac748e3684015209735b7CDd6CA6Ba5)); //pancake pair token
    }

    function() payable external {
        revert();
    }
    
    function checkAndTransferToad(uint256 _amount) private {
        require(bep20.transferFrom(msg.sender, address(this), _amount) == true, "transfer must succeed");
    }
    
    function donateToPool(uint256 _amount) public {
        require(_amount > 0 && tokenSupply > 0, "must be a positive value and have supply");
        checkAndTransferToad(_amount);
        totalDonation += _amount;
        dividendPool = dividendPool.add(_amount);
        emit onDonation(msg.sender, _amount);
    }

    function payFund() public {
        uint256 _tokensToPay = totalBurnFundCollected.sub(totalBurnFundReceived);
        require(_tokensToPay > 0);
        totalBurnFundReceived = totalBurnFundReceived.add(_tokensToPay);
        bep20.transfer(burnAddress, _tokensToPay);
    }

    function roll() hasDripped onlyDivis public {
        address _customerAddress = msg.sender;
        uint256 _dividends = myDividends();
        payoutsTo[_customerAddress] +=  (int256) (_dividends * divMagnitude);
        uint256 _tokens = purchaseTokens(_customerAddress, _dividends);
        emit onRoll(_customerAddress, _dividends, _tokens);
    }

    function withdraw() hasDripped onlyDivis public {
        address payable _customerAddress = msg.sender;
        uint256 _dividends = myDividends();
        payoutsTo[_customerAddress] += (int256) (_dividends * divMagnitude);
        bep20.transfer(_customerAddress, _dividends);
        playerStats[_customerAddress].withdrawals += _dividends;
        emit onWithdraw(_customerAddress, _dividends);
    }
    
    function buy(uint256 _amount) hasDripped public returns (uint256) {
        checkAndTransferToad(_amount);
        return purchaseTokens(msg.sender, _amount);
    }

    function _purchaseTokens(address _customerAddress, uint256 _incomingTokens) private returns(uint256) {
        uint256 _amountOfTokens = _incomingTokens;

        require(_amountOfTokens > 0 && _amountOfTokens.add(tokenSupply) > tokenSupply);

        tokenSupply = tokenSupply.add(_amountOfTokens);
        tokenBalanceLedger[_customerAddress] =  tokenBalanceLedger[_customerAddress].add(_amountOfTokens);

        int256 _updatedPayouts = (int256) (profitPerShare * _amountOfTokens);
        payoutsTo[_customerAddress] += _updatedPayouts;

        emit Transfer(address(0), _customerAddress, _amountOfTokens);

        return _amountOfTokens;
    }

    function purchaseTokens(address _customerAddress, uint256 _incomingTokens) isActivated private returns (uint256) {
        if (playerStats[_customerAddress].deposits == 0) {
            totalPlayer++;
        }

        playerStats[_customerAddress].deposits += _incomingTokens;

        require(_incomingTokens > 0);

        uint256 _dividendFee = _incomingTokens.mul(buyInFee).div(100);

        uint256 _burnFee = _incomingTokens.mul(burnFee).div(100);

        uint256 _entryFee = _incomingTokens.mul(10).div(100);
        uint256 _taxedTokens = _incomingTokens.sub(_entryFee);

        uint256 _amountOfTokens = _purchaseTokens(_customerAddress, _taxedTokens);

        dividendPool = dividendPool.add(_dividendFee);
        totalBurnFundCollected = totalBurnFundCollected.add(_burnFee);

        emit onTokenPurchase(_customerAddress, _incomingTokens, _amountOfTokens, now);

        return _amountOfTokens;
    }

    function sell(uint256 _amountOfTokens) isActivated hasDripped onlyTokenHolders public {
        address _customerAddress = msg.sender;
        require(_amountOfTokens > 0 && _amountOfTokens <= tokenBalanceLedger[_customerAddress]);

        uint256 _dividendFee = _amountOfTokens.mul(sellOutFee).div(100);
        uint256 _burnFee = _amountOfTokens.mul(burnFee).div(100);
        uint256 _taxedTokens = _amountOfTokens.sub(_dividendFee).sub(_burnFee);

        tokenSupply = tokenSupply.sub(_amountOfTokens);
        tokenBalanceLedger[_customerAddress] = tokenBalanceLedger[_customerAddress].sub(_amountOfTokens);

        int256 _updatedPayouts = (int256) (profitPerShare * _amountOfTokens + (_taxedTokens * divMagnitude));
        payoutsTo[_customerAddress] -= _updatedPayouts;

        dividendPool = dividendPool.add(_dividendFee);

        emit Transfer(_customerAddress, address(0), _amountOfTokens);
        emit onTokenSell(_customerAddress, _amountOfTokens, _taxedTokens, now);
    }

    function setName(string memory _name) onlyOwner public
    {
        name = _name;
    }

    function setSymbol(string memory _symbol) onlyOwner public
    {
        symbol = _symbol;
    }

    function totalTokenBalance() public view returns (uint256) {
        return bep20.balanceOf(address(this));
    }

    function totalSupply() public view returns(uint256) {
        return tokenSupply;
    }

    function myTokens() public view returns (uint256) {
        address _customerAddress = msg.sender;
        return balanceOf(_customerAddress);
    }

    function myEstimateDividends(bool _dayEstimate) public view returns (uint256) {
        address _customerAddress = msg.sender;
        return estimateDividendsOf(_customerAddress, _dayEstimate) ;
    }

    function estimateDividendsOf(address _customerAddress, bool _dayEstimate) public view returns (uint256) {
        uint256 _profitPerShare = profitPerShare;

        if (dividendPool > 0) {
          uint256 secondsPassed = 0;

          if (_dayEstimate == true){
            secondsPassed = 86400;
          } else {
            secondsPassed = SafeMath.sub(now, lastDripTime);
          }

          uint256 dividends = secondsPassed.mul(dividendPool).div(dailyRate);

          if (dividends > dividendPool) {
            dividends = dividendPool;
          }

          _profitPerShare = SafeMath.add(_profitPerShare, (dividends * divMagnitude) / tokenSupply);
        }

        return (uint256) ((int256) (_profitPerShare * tokenBalanceLedger[_customerAddress]) - payoutsTo[_customerAddress]) / divMagnitude;
    }

    function myDividends() public view returns (uint256) {
        address _customerAddress = msg.sender;
        return dividendsOf(_customerAddress) ;
    }

    function dividendsOf(address _customerAddress) public view returns (uint256) {
        return (uint256) ((int256) (profitPerShare * tokenBalanceLedger[_customerAddress]) - payoutsTo[_customerAddress]) / divMagnitude;
    }

    function balanceOf(address _customerAddress) public view returns (uint256) {
        return tokenBalanceLedger[_customerAddress];
    }

    function sellPrice() public pure returns (uint256) {
        uint256 _bnb = 1e18;
        uint256 _dividendFee = _bnb.mul(sellOutFee).div(100);
        uint256 _burnFee = _bnb.mul(burnFee).div(100);
        return (_bnb.sub(_dividendFee).sub(_burnFee));
    }

    function buyPrice() public pure returns(uint256) {
        uint256 _bnb = 1e18;
        uint256 _entryFee = _bnb.mul(10).div(100);
        return (_bnb.add(_entryFee));
    }

    function calculateTokensReceived(uint256 _tokensToSpend) public pure returns (uint256) {
        uint256 _entryFee = _tokensToSpend.mul(10).div(100);
        uint256 _amountOfTokens = _tokensToSpend.sub(_entryFee);

        return _amountOfTokens;
    }

    function calculateBnbReceived(uint256 _tokensToSell) public view returns (uint256) {
        require(_tokensToSell <= tokenSupply);
        uint256 _exitFee = _tokensToSell.mul(10).div(100);
        uint256 _taxedBnb = _tokensToSell.sub(_exitFee);

        return _taxedBnb;
    }

    function tokensToBurn() public view returns(uint256) {
        return totalBurnFundCollected.sub(totalBurnFundReceived);
    }
}
