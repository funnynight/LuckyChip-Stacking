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
        uint256 lotteryQuantity;
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

    function addUpdater(address _addUpdater) public onlyOwner returns (bool) {
        require(_addUpdater != address(0), "Token: _addUpdater is the zero address");
        return EnumerableSet.add(_updaters, _addUpdater);
    }

    function delUpdater(address _delUpdater) public onlyOwner returns (bool) {
        require(_delUpdater != address(0), "Token: _delUpdater is the zero address");
        return EnumerableSet.remove(_updaters, _delUpdater);
    } 

    event UpdatePower(address indexed user, uint256 quantity);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event SetMasterChef(address indexed _masterChefAddr);
    event SetBetMining(address indexed _betMiningAddr);
    event SetReferral(address indexed _referralAddr);
    event SetLottery(address indexed _lotteryAddr);

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
        lottery = ILottery(_lotteryAddr);
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
    function updateBonus(address bonusToken, uint256 amount) public override onlyUpdater {
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

    function getPower(address account) public override view returns (uint256) {
        return userInfo[account].quantity;
    }

    function updatePower(address account) public override{
        require(account != address(0), "BetMining: bet account is zero address");

        for(uint256 i = 0; i < bonusInfo.length; i ++){
            BonusInfo storage bonus = bonusInfo[i];
            if(bonus.token != address(lcToken)){
                oracle.update(bonus.token, address(lcToken));
                oracle.updateBlockInfo();
            }
        }

        UserInfo storage user = userInfo[account];
        if (user.quantity > 0) {
            for(uint256 i = 0; i < bonusInfo.length; i ++){
                BonusInfo storage bonus = bonusInfo[i];
                UserRewardInfo storage userReward = userRewardInfo[i][account];
                uint256 pendingReward = user.quantity.mul(bonus.accRewardPerShare).div(1e12).sub(userReward.rewardDebt);
                if (pendingReward > 0) {
                    userReward.pendingReward = userReward.pendingReward.add(pendingReward);
                    userReward.accRewardAmount = userReward.accRewardAmount.add(pendingReward);
                }
            }
        }

        uint256 tmpQuantity = user.quantity;
        user.quantity = 0;
        if(address(masterChef) != address(0)){
            (address[] memory tokens, uint256[] memory amounts, uint256 masterChefPower) = masterChef.getLuckyPower(account);
        }else{
            user.bankerQuantity = 0;
            user.lpQuantity = 0;
        }

        if(address(betMining) != address(0)){
            user.playerQuantity = betMining.getLuckyPower(account);
            user.quantity = user.quantity.add(user.playerQuantity);
        }else{
            user.playerQuantity = 0;
        }
        
        if(address(referral) != address(0)){
            user.referrerQuantity = referral.getLuckyPower(account);
            user.quantity = user.quantity.add(user.referrerQuantity);
        }else{
            user.referrerQuantity = 0;
        }

        if(address(lottery) != address(0)){
            user.lotteryQuantity = lottery.getLuckyPower(account);
            user.quantity = user.quantity.add(user.lotteryQuantity);
        }else{
            user.lotteryQuantity = 0;
        }

        quantity = quantity.sub(tmpQuantity).add(user.quantity);
        for(uint256 i = 0; i < bonusInfo.length; i ++){
            BonusInfo storage bonus = bonusInfo[i];
            UserRewardInfo storage userReward = userRewardInfo[i][account];
            userReward.rewardDebt = user.quantity.mul(bonus.accRewardPerShare).div(1e12);
        }

        emit UpdatePower(account, user.quantity);

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

    function setOracle(address _oracleAddr) public onlyOwner {
        require(_oracleAddr != address(0), "BetMining: new oracle is the zero address");
        oracle = IOracle(_oracleAddr);
    }

    function setMasterChef(address _masterChefAddr) public onlyOwner {
        require(_masterChefAddr != address(0), "Zero");
        masterChef = IMasterChef(_masterChefAddr);
        emit SetMasterChef(_masterChefAddr);
    }

    function setBetMining(address _betMiningAddr) public onlyOwner {
        require(_betMiningAddr != address(0), "Zero");
        betMining = IBetMining(_betMiningAddr);
        emit SetBetMining(_betMiningAddr);
    }

    function setReferral(address _referralAddr) public onlyOwner {
        require(_referralAddr != address(0), "Zero");
        referral = IReferral(_referralAddr);
        emit SetReferral(_referralAddr);
    }

    function setLottery(address _lotteryAddr) public onlyOwner {
        require(_lotteryAddr != address(0), "Zero");
        lottery = ILottery(_lotteryAddr);
        emit SetLottery(_lotteryAddr);
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
