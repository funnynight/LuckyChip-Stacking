// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./interfaces/IBEP20.sol";
import "./interfaces/IOracle.sol";
import "./interfaces/ILuckyPower.sol";
import "./interfaces/IMasterChef.sol";
import "./interfaces/IBetMining.sol";
import "./interfaces/IReferral.sol";
import "./interfaces/ILottery.sol";
import "./libraries/SafeBEP20.sol";

contract LuckyPower is ILuckyPower, Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;

    using EnumerableSet for EnumerableSet.AddressSet;
    EnumerableSet.AddressSet private _tokens;
    EnumerableSet.AddressSet private _updaters;

    // Power quantity info of each user.
    struct UserInfo {
        uint256 quantity;
        uint256 lpQuantity;
        uint256 bankerQuantity;
        uint256 playerQuantity;
        uint256 referrerQuantity;
        uint256 accQuantity;
    }

    // Reward info of each user for each bonus
    struct UserRewardInfo {
        uint256 pendingReward;
        uint256 rewardDebt;
        uint256 accRewardAmount;
    }

    // Info of each pool.
    struct BonusInfo {
        address token; // Address of bonus token contract.
        uint256 lastRewardBlock; // Last block number that reward tokens distribution occurs.
        uint256 accRewardPerShare; // Accumulated reward tokens per share, times 1e12.
        uint256 allocRewardAmount;
        uint256 accRewardAmount;
    }

    uint256 public quantity;
    uint256 public accQuantity;

    uint256 private unlocked = 1;

    // Lc token
    IBEP20 public lcToken;
    // Info of each bonus.
    BonusInfo[] public bonusInfo;
    // token address to its corresponding id
    mapping(address => uint256) public tokenIdMap;
    // Info of each user that stakes LP tokens.
    mapping(address => UserInfo) public userInfo;
    // user pending bonus 
    mapping(uint256 => mapping(address => UserRewardInfo)) public userRewardInfo;

    IOracle public oracle;
    IMasterChef public masterChef;
    IBetMining public betMining;
    IReferral public referral;
    ILottery public lottery;

    function isUpdater(address account) public view returns (bool) {
        return EnumerableSet.contains(_updaters, account);
    }

    // modifier for mint function
    modifier onlyUpdater() {
        require(isUpdater(msg.sender), "caller is not a updater");
        _;
    }

    // lock modifier
    modifier lock() {
        require(unlocked == 1, 'LuckyPower: LOCKED');
        unlocked = 0;
        _;
        unlocked = 1;
    }

    function addUpdater(address _addUpdater) public onlyOwner returns (bool) {
        require(_addUpdater != address(0), "Token: _addUpdater is the zero address");
        return EnumerableSet.add(_updaters, _addUpdater);
    }

    function delUpdater(address _delUpdater) public onlyOwner returns (bool) {
        require(_delUpdater != address(0), "Token: _delUpdater is the zero address");
        return EnumerableSet.remove(_updaters, _delUpdater);
    } 

    event UpdatePower(address indexed user, uint256 lpPower, uint256 bankerPower, uint256 playerPower);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

    constructor(
        address _lcTokenAddr,
        address _oracleAddr,
        address _masterChefAddr,
        address _betMiningAddr,
        address _referralAddr,
        address _lotteryAddr
    ) public {
        lcToken = IBEP20(_lcTokenAddr);
        oracle = IOracle(_oracleAddr);
        masterChef = IMasterChef(_masterChefAddr);
        betMining = IBetMining(_betMiningAddr);
        referral = IReferral(_referralAddr);
        lottery = ILottery(_referralAddr);
    }

    // Add a new token to the pool. Can only be called by the owner.
    function addBonus(address _token) public onlyOwner {
        require(_token != address(0), "BetMining: _token is the zero address");

        require(!EnumerableSet.contains(_tokens, _token), "BetMining: _token is already added to the pool");
        // return EnumerableSet.add(_tokens, _token);
        EnumerableSet.add(_tokens, _token);

        bonusInfo.push(
            BonusInfo({
                token: _token,
                lastRewardBlock: block.number,
                accRewardPerShare: 0,
                allocRewardAmount: 0,
                accRewardAmount: 0
            })
        );
        tokenIdMap[_token] = getBonusLength() - 1;
    }

    // Update reward variables of the given pool to be up-to-date.
    function updateBonus(address bonusToken, uint256 amount) public override onlyUpdater lock {
        uint256 bonusId = tokenIdMap[bonusToken];
        require(bonusId < bonusInfo.length, "BonusId must be less than bonusInfo length");

        BonusInfo storage bonus = bonusInfo[bonusId];
        if(bonus.token != bonusToken || quantity <= 0){
            return;
        }

        // TODO update dev quantity
        bonus.accRewardPerShare = bonus.accRewardPerShare.add(amount.mul(1e12).div(quantity));
        bonus.allocRewardAmount = bonus.allocRewardAmount.add(amount);
        bonus.accRewardAmount = bonus.accRewardAmount.add(amount);
        bonus.lastRewardBlock = block.number;
    }

    function updatePower(address account) public onlyUpdater returns (bool) {
        require(account != address(0), "BetMining: bet account is zero address");

        if (getBonusLength() <= 0) {
            return false;
        }

        PoolInfo storage pool = poolInfo[tokenOfPid[token]];
        // If it does not exist or the allocPoint is 0 then return
        if (pool.token != token || pool.allocPoint <= 0) {
            return false;
        }

        uint256 quantity = oracle.getQuantity(token, amount);
        if (quantity <= 0) {
            return false;
        }

        updatePool(tokenOfPid[token]);
        if(token != address(rewardToken)){
            oracle.update(token, address(rewardToken));
            oracle.updateBlockInfo();
        }

        UserInfo storage user = userInfo[tokenOfPid[token]][account];
        if (user.quantity > 0) {
            uint256 pendingReward = user.quantity.mul(pool.accRewardPerShare).div(1e12).sub(user.rewardDebt);
            if (pendingReward > 0) {
                user.pendingReward = user.pendingReward.add(pendingReward);
            }
        }

        if (quantity > 0) {
            pool.quantity = pool.quantity.add(quantity);
            pool.accQuantity = pool.accQuantity.add(quantity);
            totalQuantity = totalQuantity.add(quantity);
            user.quantity = user.quantity.add(quantity);
            user.accQuantity = user.accQuantity.add(quantity);
        }
        user.rewardDebt = user.quantity.mul(pool.accRewardPerShare).div(1e12);
        emit Swap(account, tokenOfPid[token], quantity);

        return true;
    }

    function getPower(address account) public view returns (uint256) {
        return userInfo[account].quantity;
    }

    /*
    function pendingRewards(uint256 _pid, address _user) public view validPool(_pid) returns (uint256) {

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accRewardPerShare = pool.accRewardPerShare;

        if (user.quantity > 0) {
            if (block.number > pool.lastRewardBlock) {
                uint256 blockReward = getRewardTokenBlockReward(pool.lastRewardBlock);
                uint256 tokenReward = blockReward.mul(pool.allocPoint).div(totalAllocPoint);
                accRewardPerShare = accRewardPerShare.add(tokenReward.mul(1e12).div(pool.quantity));
                return user.pendingReward.add(user.quantity.mul(accRewardPerShare).div(1e12).sub(user.rewardDebt));
            }
            if (block.number == pool.lastRewardBlock) {
                return user.pendingReward.add(user.quantity.mul(accRewardPerShare).div(1e12).sub(user.rewardDebt));
            }
        }
        return 0;
    }

    function withdraw() public{
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][tx.origin];

        updatePool(_pid);
        uint256 pendingAmount = pendingRewards(_pid, tx.origin);

        if (pendingAmount > 0) {
            safeRewardTokenTransfer(tx.origin, pendingAmount);
            pool.quantity = pool.quantity.sub(user.quantity);
            pool.allocRewardAmount = pool.allocRewardAmount.sub(pendingAmount);
            user.accRewardAmount = user.accRewardAmount.add(pendingAmount);
            user.quantity = 0;
            user.rewardDebt = 0;
            user.pendingReward = 0;
        }
        emit Withdraw(tx.origin, _pid, pendingAmount);
    }

    
    function emergencyWithdraw() public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        uint256 pendingReward = user.pendingReward;
        pool.quantity = pool.quantity.sub(user.quantity);
        pool.allocRewardAmount = pool.allocRewardAmount.sub(user.pendingReward);
        user.accRewardAmount = user.accRewardAmount.add(user.pendingReward);
        user.quantity = 0;
        user.rewardDebt = 0;
        user.pendingReward = 0;

        safeRewardTokenTransfer(msg.sender, pendingReward);

        emit EmergencyWithdraw(msg.sender, _pid, user.quantity);
    }
    */

    // Safe reward token transfer function, just in case if rounding error causes pool to not have enough reward tokens.
    function safeRewardTokenTransfer(address _to, uint256 _amount) internal {
        uint256 rewardTokenBalance = rewardToken.balanceOf(address(this));
        if (_amount > rewardTokenBalance) {
            IBEP20(rewardToken).safeTransfer(_to, rewardTokenBalance);
        } else {
            IBEP20(rewardToken).safeTransfer(_to, _amount);
        }
    }

    function setOracle(address _oracleAddr) public onlyOwner {
        require(_oracleAddr != address(0), "BetMining: new oracle is the zero address");
        oracle = IOracle(_oracleAddr);
    }

    function getLpTokensLength() public view returns (uint256) {
        return EnumerableSet.length(_tokens);
    }

    function getLpToken(uint256 _index) public view returns (address) {
        return EnumerableSet.at(_tokens, _index);
    }

    function getUpdaterLength() public view returns (uint256) {
        return EnumerableSet.length(_updaters);
    }

    function getUpdater(uint256 _index) public view returns (address) {
        return EnumerableSet.at(_updaters, _index);
    }

    function getBonusLength() public view returns (uint256) {
        return bonusInfo.length;
    }

}
