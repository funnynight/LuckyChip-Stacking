// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./interfaces/IBEP20.sol";
import "./interfaces/IReferral.sol";
import "./interfaces/ILuckyPower.sol";
import "./libraries/SafeBEP20.sol";

contract Referral is IReferral, Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;
    using EnumerableSet for EnumerableSet.AddressSet;
   
    EnumerableSet.AddressSet private _operators; 
    IBEP20 public lcToken;
    ILuckyPower public luckyPower;

    struct ReferrerInfo{
        uint256 lpCommission;
        uint256 bankerCommission;
        uint256 playerCommission;
        uint256 pending;
    }

    mapping(address => address) public referrers; // user address => referrer address
    mapping(address => uint256) public referralsCount; // referrer address => referrals count
    mapping(address => ReferrerInfo) public referrerInfo; // referrer address => Referrer Info

    event ReferrerRecorded(address indexed user, address indexed referrer);
    event LpCommissionRecorded(address indexed referrer, uint256 commission);
    event BankerCommissionRecorded(address indexed referrer, uint256 commission);
    event PlayerCommissionRecorded(address indexed referrer, uint256 commission);
    event Claim(address indexed referrer, uint256 amount);
    event SetLuckyPower(address indexed _luckyPowerAddr);


    constructor(address _lcTokenAddr) public {
        lcToken = IBEP20(_lcTokenAddr);
    }

    function isOperator(address account) public view returns (bool) {
        return EnumerableSet.contains(_operators, account);
    }

    // modifier for operator
    modifier onlyOperator() {
        require(isOperator(msg.sender), "caller is not a operator");
        _;
    }

    function addOperator(address _addOperator) public onlyOwner returns (bool) {
        require(_addOperator != address(0), "Token: _addOperator is the zero address");
        return EnumerableSet.add(_operators, _addOperator);
    }

    function delOperator(address _delOperator) public onlyOwner returns (bool) {
        require(_delOperator != address(0), "Token: _delOperator is the zero address");
        return EnumerableSet.remove(_operators, _delOperator);
    }

    function recordReferrer(address _user, address _referrer) public override onlyOperator {
        if (_user != address(0)
            && _referrer != address(0)
            && _user != _referrer
            && referrers[_user] == address(0)
        ) {
            referrers[_user] = _referrer;
            referralsCount[_referrer] = referralsCount[_referrer].add(1);
            emit ReferrerRecorded(_user, _referrer);
        }
    }

    function recordLpCommission(address _referrer, uint256 _commission) public override onlyOperator {
        if (_referrer != address(0) && _commission > 0) {
            ReferrerInfo storage info = referrerInfo[_referrer];
            info.lpCommission = info.lpCommission.add(_commission);
            info.pending = info.pending.add(_commission);

            emit LpCommissionRecorded(_referrer, _commission);
        }
    }

    function recordBankerCommission(address _referrer, uint256 _commission) public override onlyOperator {
        if (_referrer != address(0) && _commission > 0) {
            ReferrerInfo storage info = referrerInfo[_referrer];
            info.bankerCommission = info.bankerCommission.add(_commission);
            info.pending = info.pending.add(_commission);
            
            emit BankerCommissionRecorded(_referrer, _commission);
        }
    }

    function recordPlayerCommission(address _referrer, uint256 _commission) public override onlyOperator {
        if (_referrer != address(0) && _commission > 0) {
            ReferrerInfo storage info = referrerInfo[_referrer];
            info.playerCommission = info.playerCommission.add(_commission);
            info.pending = info.pending.add(_commission);
            
            emit PlayerCommissionRecorded(_referrer, _commission);
        }
    }

    // Get the referrer address that referred the user
    function getReferrer(address _user) public override view returns (address) {
        return referrers[_user];
    }

    function getReferralCommission(address _referrer) public override view returns(uint256, uint256, uint256){
        return (referrerInfo[_referrer].lpCommission, referrerInfo[_referrer].bankerCommission, referrerInfo[_referrer].playerCommission);
    }

    function getLuckyPower(address _referrer) public override view returns (uint256){
        return referrerInfo[_referrer].pending;
    }

    function claim() public override nonReentrant {
        address referrer = msg.sender;
        ReferrerInfo storage info = referrerInfo[referrer];
        if(info.pending > 0){
            uint256 tmpAmount = info.pending;
            info.pending = 0;
            lcToken.safeTransfer(referrer, tmpAmount);
            if(address(luckyPower) != address(0)){
                luckyPower.updatePower(referrer);
            }
            emit Claim(referrer, tmpAmount);
        }
    }

    function setLuckyPower(address _luckyPowerAddr) public onlyOwner {
        require(_luckyPowerAddr != address(0), "Zero");
        luckyPower = ILuckyPower(_luckyPowerAddr);
        emit SetLuckyPower(_luckyPowerAddr);
    }
}
