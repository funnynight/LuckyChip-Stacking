// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "./interfaces/IBEP20.sol";
import "./interfaces/IMiningOracle.sol";
import "./libraries/SafeBEP20.sol";
import "./LCToken.sol";

contract BetMining is Ownable {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;

    using EnumerableSet for EnumerableSet.AddressSet;
    EnumerableSet.AddressSet private _betTables;
    EnumerableSet.AddressSet private _tokens;

    // Info of each user.
    struct UserInfo {
        uint256 quantity;
        uint256 accQuantity;
        uint256 pendingReward;
        uint256 rewardDebt; // Reward debt.
        uint256 accRewardAmount; // How many rewards the user has got.
    }

    struct UserView {
        uint256 quantity;
        uint256 accQuantity;
        uint256 unclaimedRewards;
        uint256 accRewardAmount;
    }

    // Info of each pool.
    struct PoolInfo {
        address token; // Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. reward tokens to distribute per block.
        uint256 lastRewardBlock; // Last block number that reward tokens distribution occurs.
        uint256 accRewardPerShare; // Accumulated reward tokens per share, times 1e12.
        uint256 quantity;
        uint256 accQuantity;
        uint256 allocRewardAmount;
        uint256 accRewardAmount;
    }

    struct PoolView {
        uint256 pid;
        address token;
        uint256 allocPoint;
        uint256 lastRewardBlock;
        uint256 rewardsPerBlock;
        uint256 accRewardPerShare;
        uint256 allocRewardAmount;
        uint256 accRewardAmount;
        uint256 quantity;
        uint256 accQuantity;
        string symbol;
        string name;
        uint8 decimals;
    }

    // The reward token!
    LCToken public rewardToken;
    // reward tokens created per block.
    uint256 public rewardTokenPerBlock;
    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // pid corresponding address
    mapping(address => uint256) public tokenOfPid;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    uint256 public totalQuantity = 0;
    IMiningOracle public oracle;
    // The block number when reward token mining starts.
    uint256 public startBlock;
    uint256 public halvingPeriod = 3952800; // half year

    modifier validPool(uint256 _pid){
        require(_pid < poolInfo.length, 'pool not exist');
        _;
    }

    function isBetTable(address account) public view returns (bool) {
        return EnumerableSet.contains(_betTables, account);
    }

    // modifier for mint function
    modifier onlyBetTable() {
        require(isBetTable(msg.sender), "caller is not a bet table");
        _;
    }

    function addBetTable(address _addBetTable) public onlyOwner returns (bool) {
        require(_addBetTable != address(0), "Token: _addBetTable is the zero address");
        return EnumerableSet.add(_betTables, _addBetTable);
    }

    function delBetTable(address _delBetTable) public onlyOwner returns (bool) {
        require(_delBetTable != address(0), "Token: _delBetTable is the zero address");
        return EnumerableSet.remove(_betTables, _delBetTable);
    }

    event Swap(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

    constructor(
        address _rewardTokenAddr,
        address _oracleAddr,
        uint256 _rewardTokenPerBlock,
        uint256 _startBlock
    ) public {
        rewardToken = LCToken(_rewardTokenAddr);
        oracle = IMiningOracle(_oracleAddr);
        rewardTokenPerBlock = _rewardTokenPerBlock;
        startBlock = _startBlock;
    }

    function phase(uint256 blockNumber) public view returns (uint256) {
        if (halvingPeriod == 0) {
            return 0;
        }
        if (blockNumber > startBlock) {
            return (blockNumber.sub(startBlock)).div(halvingPeriod);
        }
        return 0;
    }

    function getRewardTokenPerBlock(uint256 blockNumber) public view returns (uint256) {
        uint256 _phase = phase(blockNumber);
        return rewardTokenPerBlock.div(2**_phase);
    }

    function getRewardTokenBlockReward(uint256 _lastRewardBlock) public view returns (uint256) {
        uint256 blockReward = 0;
        uint256 lastRewardPhase = phase(_lastRewardBlock);
        uint256 currentPhase = phase(block.number);
        while (lastRewardPhase < currentPhase) {
            lastRewardPhase++;
            uint256 height = lastRewardPhase.mul(halvingPeriod).add(startBlock);
            blockReward = blockReward.add((height.sub(_lastRewardBlock)).mul(getRewardTokenPerBlock(height)));
            _lastRewardBlock = height;
        }
        blockReward = blockReward.add((block.number.sub(_lastRewardBlock)).mul(getRewardTokenPerBlock(block.number)));
        return blockReward;
    }

    // Add a new token to the pool. Can only be called by the owner.
    function add(
        uint256 _allocPoint,
        address _token,
        bool _withUpdate
    ) public onlyOwner {
        require(_token != address(0), "BetMining: _token is the zero address");

        require(!EnumerableSet.contains(_tokens, _token), "BetMining: _token is already added to the pool");
        // return EnumerableSet.add(_tokens, _token);
        EnumerableSet.add(_tokens, _token);

        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(
            PoolInfo({
                token: _token,
                allocPoint: _allocPoint,
                lastRewardBlock: lastRewardBlock,
                accRewardPerShare: 0,
                quantity: 0,
                accQuantity: 0,
                allocRewardAmount: 0,
                accRewardAmount: 0
            })
        );
        tokenOfPid[_token] = getPoolLength() - 1;
    }

    // Update the given pool's reward token allocation point. Can only be called by the owner.
    function set(
        uint256 _pid,
        uint256 _allocPoint,
        bool _withUpdate
    ) public onlyOwner {
        require(_pid < poolInfo.length, "overflow");

        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }

        if (pool.quantity == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }

        uint256 blockReward = getRewardTokenBlockReward(pool.lastRewardBlock);

        if (blockReward <= 0) {
            return;
        }

        uint256 tokenReward = blockReward.mul(pool.allocPoint).div(totalAllocPoint);
        pool.lastRewardBlock = block.number;

        pool.accRewardPerShare = pool.accRewardPerShare.add(tokenReward.mul(1e12).div(pool.quantity));
        pool.allocRewardAmount = pool.allocRewardAmount.add(tokenReward);
        pool.accRewardAmount = pool.accRewardAmount.add(tokenReward);

        rewardToken.mint(address(this), tokenReward);
    }

    function bet(
        address account,
        address token,
        uint256 amount
    ) public onlyBetTable returns (bool) {
        require(account != address(0), "BetMining: bet account is zero address");
        require(token != address(0), "BetMining: token is zero address");

        if (getPoolLength() <= 0) {
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

    function withdraw(uint256 _pid) public validPool(_pid) {
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

    function harvestAll() public {
        for (uint256 i = 0; i < poolInfo.length; i++) {
            withdraw(i);
        }
    }

    function emergencyWithdraw(uint256 _pid) public validPool(_pid) {
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

    // Safe reward token transfer function, just in case if rounding error causes pool to not have enough reward tokens.
    function safeRewardTokenTransfer(address _to, uint256 _amount) internal {
        uint256 rewardTokenBalance = rewardToken.balanceOf(address(this));
        if (_amount > rewardTokenBalance) {
            IBEP20(rewardToken).safeTransfer(_to, rewardTokenBalance);
        } else {
            IBEP20(rewardToken).safeTransfer(_to, _amount);
        }
    }

    // Set the number of reward token produced by each block
    function setRewardTokenPerBlock(uint256 _newPerBlock) public onlyOwner {
        massUpdatePools();
        rewardTokenPerBlock = _newPerBlock;
    }

    function setHalvingPeriod(uint256 _block) public onlyOwner {
        halvingPeriod = _block;
    }

    function setOracle(address _oracleAddr) public onlyOwner {
        require(_oracleAddr != address(0), "BetMining: new oracle is the zero address");
        oracle = IMiningOracle(_oracleAddr);
    }

    function getLpTokensLength() public view returns (uint256) {
        return EnumerableSet.length(_tokens);
    }

    function getLpToken(uint256 _index) public view returns (address) {
        return EnumerableSet.at(_tokens, _index);
    }

    function getBetTableLength() public view returns (uint256) {
        return EnumerableSet.length(_betTables);
    }

    function getBetTable(uint256 _index) public view returns (address) {
        return EnumerableSet.at(_betTables, _index);
    }

    function getPoolLength() public view returns (uint256) {
        return poolInfo.length;
    }

    function getAllPools() external view returns (PoolInfo[] memory) {
        return poolInfo;
    }

    function getPoolView(uint256 _pid) public view validPool(_pid) returns (PoolView memory) {
        PoolInfo memory pool = poolInfo[_pid];
        IBEP20 tmpToken = IBEP20(pool.token);
        uint256 rewardsPerBlock = pool.allocPoint.mul(rewardTokenPerBlock).div(totalAllocPoint);
        return
            PoolView({
                pid: _pid,
                token: pool.token,
                allocPoint: pool.allocPoint,
                lastRewardBlock: pool.lastRewardBlock,
                accRewardPerShare: pool.accRewardPerShare,
                rewardsPerBlock: rewardsPerBlock,
                allocRewardAmount: pool.allocRewardAmount,
                accRewardAmount: pool.accRewardAmount,
                quantity: pool.quantity,
                accQuantity: pool.accQuantity,
                symbol: tmpToken.symbol(),
                name: tmpToken.name(),
                decimals: tmpToken.decimals()
            });
    }

    function getPoolViewByAddress(address token) public view returns (PoolView memory) {
        uint256 pid = tokenOfPid[token];
        return getPoolView(pid);
    }

    function getAllPoolViews() external view returns (PoolView[] memory) {
        PoolView[] memory views = new PoolView[](poolInfo.length);
        for (uint256 i = 0; i < poolInfo.length; i++) {
            views[i] = getPoolView(i);
        }
        return views;
    }

    function getUserView(address token, address account) public view returns (UserView memory) {
        uint256 pid = tokenOfPid[token];
        UserInfo memory user = userInfo[pid][account];
        uint256 unclaimedRewards = pendingRewards(pid, account);
        return
            UserView({
                quantity: user.quantity,
                accQuantity: user.accQuantity,
                unclaimedRewards: unclaimedRewards,
                accRewardAmount: user.accRewardAmount
            });
    }

    function getUserViews(address account) external view returns (UserView[] memory) {
        address token;
        UserView[] memory views = new UserView[](poolInfo.length);
        for (uint256 i = 0; i < poolInfo.length; i++) {
            token = address(poolInfo[i].token);
            views[i] = getUserView(token, account);
        }
        return views;
    }

}
