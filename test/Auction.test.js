const { ethers } = require("hardhat");
const { expect } = require("chai");
const { BigNumber } = require("ethers");

describe("Marketplace Auction",function(){

    let deployer, creator, alice , bob
    let marketplace,nft

    const ETHER_AMOUNT = ethers.utils.parseEther("0.5");
    const INITIAL_BID = ethers.utils.parseEther("1");
    const NEXT_BID = ethers.utils.parseEther("2")

    beforeEach(async function(){
        [deployer,creator,alice,bob] =  await ethers.getSigners();

        const nftMarketFactory =  await ethers.getContractFactory("NftMarketPlaceAuction",deployer)

        marketplace =  await nftMarketFactory.deploy()
        
        const nftCollectionFactory = await ethers.getContractFactory("GHLocaleNFT",deployer);

        nft = await nftCollectionFactory.deploy()

        await nft.connect(creator).mint({value:ETHER_AMOUNT});

        //approve market place to use nft
        await nft.connect(creator).approve(await marketplace.address,1);
        

    })
    describe("Auction created", function(){

    it("should revert if not owner of nft", async function(){

        await expect(marketplace.connect(deployer).createAuction(await nft.address,1,INITIAL_BID,await marketplace.getTimestamp()+400)).to.
        be.revertedWith("Not owner")
    })

    it("should emit an event when auction is created",async function(){

        await expect(marketplace.connect(creator).createAuction(await nft.address,1,INITIAL_BID,await marketplace.getTimestamp()+400)).to
        .emit(marketplace,"AuctionCreated")
    })

    })

    describe("Place Bid", function(){
        beforeEach(async function(){
           await  marketplace.connect(creator).createAuction(await nft.address,1,INITIAL_BID,await marketplace.getTimestamp()+6000)
        })
        it.only("should emit an event if bid is placed",async function(){
            await expect(marketplace.connect(alice).placeBid(0,{value:NEXT_BID + 1})).to.emit(marketplace,"BidPlaced")

        })
        it("should revert if auction has ended",async function(){
            await ethers.provider.send("evm_increaseTime", [5 * 24 * 60 * 60]);
            await expect(marketplace.connect(alice).placeBid(0,{value:NEXT_BID})).to.be.revertedWith("Auction Ended")
        })
    })

})
