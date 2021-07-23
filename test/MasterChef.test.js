const { expectRevert, time } = require('@openzeppelin/test-helpers');
const { AddressZero } = require("@ethersproject/constants")
const { assert } = require('chai');
const JSBI           = require('jsbi')
const LCToken = artifacts.require('LCToken');
const MasterChef = artifacts.require('MasterChef');
const MockBEP20 = artifacts.require('libs/MockBEP20');
//let perBlock = '100000000000000000000';
let perBlock = '1000';
const delay = ms => new Promise(res => setTimeout(res, ms));
contract('MasterChef', ([alice, bob, carol, dev, refFeeAddr, minter]) => {
    beforeEach(async () => {
        this.lc = await LCToken.new({ from: minter });
    
        this.lp1 = await MockBEP20.new('LPToken', 'LP1', '1000000', { from: minter });
        this.lp2 = await MockBEP20.new('LPToken', 'LP2', '1000000', { from: minter });
        this.lp3 = await MockBEP20.new('LPToken', 'LP3', '1000000', { from: minter });
        
        await this.lc.addMinter(minter, { from: minter });
        this.chef = await MasterChef.new(this.lc.address, dev, refFeeAddr, perBlock, '100', '900000','90000', '10000', { from: minter });
        await this.lc.addMinter(this.chef.address, { from: minter });
    
        await this.lp1.transfer(alice, '2000', { from: minter });
        await this.lp2.transfer(alice, '2000', { from: minter });
        await this.lp3.transfer(alice, '2000', { from: minter });

        await this.lp1.transfer(bob, '2000', { from: minter });
        await this.lp1.transfer(carol, '2000', { from: minter });
        await this.lp2.transfer(bob, '2000', { from: minter });
        await this.lp2.transfer(carol, '2000', { from: minter });
       // await this.lp3.transfer(bob, '2000', { from: minter });
    });
    it('real case', async () => {
        await this.chef.add('1000', '0', this.lp1.address, true, { from: minter });
		assert.equal((await this.chef.poolLength()).toString(), "1");
		assert.equal((await this.chef.totalAllocPoint()).toString(), "1000");
		assert.equal((await this.chef.totalBonusPoint()).toString(), "0");
        await this.chef.addBonus(this.lp3.address, { from: minter });
		assert.equal((await this.chef.bonusLength()).toString(), "1");
		console.log(`startBlock: ${(await this.chef.startBlock())}`);

        //1 - lp
        await this.lp1.approve(this.chef.address, '1000', { from: alice });
        await this.lc.approve(this.chef.address, '1000', { from: alice });
        console.log('----Deposit----');
		assert.equal((await this.lc.balanceOf(alice)).toString(), '0');
        await time.advanceBlockTo('150');
		console.log(`Current block: ${(await time.latestBlock())}`);
        await this.chef.deposit(0, '20', AddressZero, { from: alice });
		let user = await this.chef.userInfo(0, alice, {from: alice});
		console.log(`${user[0]},${user[1]}`);
		console.log((await this.chef.pendingLC(0, alice)).toString());
        await time.advanceBlockTo('170');
		console.log((await this.chef.pendingLC(0, alice)).toString());
        console.log('---Withdraw---');
		console.log((await this.chef.pendingLC(0, alice)).toString());
		console.log(`Current block: ${(await time.latestBlock())}`);
        await time.advanceBlockTo('200'); 
        await this.chef.withdraw(0, '20', { from: alice });
		user = await this.chef.userInfo(0, alice, {from: alice});
		console.log(`${user[0]},${user[1]}`);
        let aliceBalance = await this.lc.balanceOf(alice);
        console.log('alice balance: ', aliceBalance.toString());
		console.log(`Current block: ${(await time.latestBlock())}`);

        console.log('---------------');

        await time.advanceBlockTo('210'); 
        await this.chef.withdrawDevFee({ from: minter });
        let balanceDev = await this.lc.balanceOf(dev);
        console.log('dev address balance: ', balanceDev.toString());
        let balanceRef = await this.lc.balanceOf(refFeeAddr);
        console.log('ref address balance: ', balanceRef.toString());
    })
    it('bonus', async () => {
        await this.chef.add('1000', '90', this.lp1.address, true, { from: minter });
		assert.equal((await this.chef.poolLength()).toString(), "1");
		pool = await this.chef.poolInfo(0, {from:minter});
		console.log(`${pool[0]},${pool[1]},${pool[2]},${pool[3]},${pool[4]}`);
        await this.chef.addBonus(this.lp3.address, { from: minter });
		assert.equal((await this.chef.bonusLength()).toString(), "1");
		bonusPool = await this.chef.bonusInfo(0, {from:minter});
		console.log(`${bonusPool[0]},${bonusPool[1]}`);
		console.log((await this.chef.totalBonusPoint()).toString());

        await this.lp1.approve(this.chef.address, '1000000', { from: alice });
        await this.lp3.approve(this.chef.address, '1000000', { from: minter });
        await this.lc.approve(this.chef.address, '1000000', { from: alice });
        await this.lp3.approve(this.chef.address, '1000000', { from: alice });
		assert.equal((await this.lp3.balanceOf(alice)).toString(), '2000');
		bonusPerShare = await this.chef.poolBonusPerShare(0, 0);
		console.log(`${bonusPerShare}`);
        await time.advanceBlockTo('300');
		console.log(`Current block: ${(await time.latestBlock())}`);
        await this.chef.deposit(0, '20', AddressZero, { from: alice });
		await this.chef.updateBonus(0, '100', { from: minter});
		bonusPool = await this.chef.bonusInfo(0, {from:minter});
		console.log(`${bonusPool[0]},${bonusPool[1]}`);
		user = await this.chef.userInfo(0, alice, {from: alice});
		console.log(`${user[0]},${user[1]}`);
		userBonusDebt = await this.chef.userBonusDebt(0, alice, {from: alice});	
		console.log(`${userBonusDebt}`);
		bonusPerShare = await this.chef.poolBonusPerShare(0, 0);
		console.log(`${bonusPerShare}`);
		assert.equal((await this.lp3.balanceOf(this.chef.address)).toString(), '100');
		pendingBonus = await this.chef.pendingBonus(0, alice);
		console.log(`${pendingBonus[0]}}`);
		

        await time.advanceBlockTo('350'); 
        await this.chef.withdraw(0, '20', { from: alice });

        let aliceBalance = await this.lc.balanceOf(alice);
        console.log('alice balance: ', aliceBalance.toString());
        aliceBalance = await this.lp3.balanceOf(alice);
        console.log('alice lp3 balance: ', aliceBalance.toString());
	
	});

});
