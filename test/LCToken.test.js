const { assert } = require("chai");

const LCToken = artifacts.require('LCToken');

contract('LCToken', ([alice, bob, carol, dev, minter]) => {
    beforeEach(async () => {
        this.lc = await LCToken.new({ from: minter });
    });


    it('mint', async () => {
		await this.lc.addMinter(minter, { from: minter });
        await this.lc.mint(alice, 1000, { from: minter });
        assert.equal((await this.lc.balanceOf(alice)).toString(), '1000');
    })
});
