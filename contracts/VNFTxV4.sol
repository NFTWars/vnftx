pragma solidity ^0.6.0;

import "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/introspection/IERC165Upgradeable.sol";

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";

// @TODO DOn't Forget!!!
import "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155HolderUpgradeable.sol";

import "@openzeppelin/contracts-upgradeable/utils/EnumerableSetUpgradeable.sol";

import "../interfaces/IMuseToken.sol";
import "../interfaces/IVNFT.sol";
import "hardhat/console.sol";

// SPDX-License-Identifier: MIT

// Extending IERC1155 with mint and burn
interface IERC1155 is IERC165Upgradeable {
    event TransferSingle(
        address indexed operator,
        address indexed from,
        address indexed to,
        uint256 id,
        uint256 value
    );

    event TransferBatch(
        address indexed operator,
        address indexed from,
        address indexed to,
        uint256[] ids,
        uint256[] values
    );

    event ApprovalForAll(
        address indexed account,
        address indexed operator,
        bool approved
    );

    event URI(string value, uint256 indexed id);

    function balanceOf(address account, uint256 id)
        external
        view
        returns (uint256);

    function balanceOfBatch(address[] calldata accounts, uint256[] calldata ids)
        external
        view
        returns (uint256[] memory);

    function setApprovalForAll(address operator, bool approved) external;

    function isApprovedForAll(address account, address operator)
        external
        view
        returns (bool);

    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes calldata data
    ) external;

    function safeBatchTransferFrom(
        address from,
        address to,
        uint256[] calldata ids,
        uint256[] calldata amounts,
        bytes calldata data
    ) external;

    function mint(
        address to,
        uint256 id,
        uint256 amount,
        bytes calldata data
    ) external;

    function mintBatch(
        address to,
        uint256[] calldata ids,
        uint256[] calldata amounts,
        bytes calldata data
    ) external;

    function burn(
        address account,
        uint256 id,
        uint256 value
    ) external;

    function burnBatch(
        address account,
        uint256[] calldata ids,
        uint256[] calldata values
    ) external;
}

contract VNFTxV4 is
    Initializable,
    OwnableUpgradeable,
    ERC1155HolderUpgradeable
{
    /* START V1  STORAGE */
    using SafeMathUpgradeable for uint256;

    bool paused;

    IVNFT public vnft;
    IMuseToken public muse;
    IERC1155 public addons;

    uint256 public artistPct;

    struct Addon {
        string _type;
        uint256 price;
        uint256 requiredhp;
        uint256 rarity;
        string artistName;
        address artistAddr;
        uint256 quantity;
        uint256 used;
    }

    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;

    mapping(uint256 => Addon) public addon;

    mapping(uint256 => EnumerableSetUpgradeable.UintSet) private addonsConsumed;
    EnumerableSetUpgradeable.UintSet lockedAddons;

    //nftid to rarity points
    mapping(uint256 => uint256) public rarity;
    mapping(uint256 => uint256) public challengesUsed;

    //!important, decides which gem score hp is based of
    uint256 public healthGemScore;
    uint256 public healthGemId;
    uint256 public healthGemPrice;
    uint256 public healthGemDays;

    // premium hp is the min requirement for premium features.
    uint256 public premiumHp;
    uint256 public hpMultiplier;
    uint256 public rarityMultiplier;
    uint256 public addonsMultiplier;
    //expected addons to be used for max hp
    uint256 public expectedAddons;
    //Expected rarity, this should be changed according to new addons introduced.
    uint256 expectedRarity;

    using CountersUpgradeable for CountersUpgradeable.Counter;
    CountersUpgradeable.Counter private _addonId;

    /* END V1 STORAGE */

    event BuyAddon(uint256 nftId, uint256 addon, address player);
    event CreateAddon(
        uint256 addonId,
        string _type,
        uint256 rarity,
        uint256 quantity
    );
    event EditAddon(
        uint256 addonId,
        string _type,
        uint256 price,
        uint256 _quantity
    );
    event AttachAddon(uint256 addonId, uint256 nftId);
    event RemoveAddon(uint256 addonId, uint256 nftId);

    uint256 cashbackPct;

    mapping(uint256 => uint256) public hpLostOnBattle;
    mapping(uint256 => uint256) public timesAttacked;

    mapping(address => uint256) public toReceiveCashback;

    constructor() public {}

    // remove this for laucnch
    function initialize(
        IVNFT _vnft,
        IMuseToken _muse,
        IERC1155 _addons
    ) public initializer {
        vnft = _vnft;
        muse = _muse;
        addons = _addons;
        paused = false;
        artistPct = 5;
        healthGemScore = 100;
        healthGemId = 1;
        healthGemPrice = 13 * 10**18;
        healthGemDays = 1;
        premiumHp = 50;
        hpMultiplier = 70;
        rarityMultiplier = 15;
        addonsMultiplier = 15;
        expectedAddons = 10;
        expectedRarity = 300;
        OwnableUpgradeable.__Ownable_init();
        cashbackPct = 40;
    }

    modifier tokenOwner(uint256 _id) {
        require(
            vnft.ownerOf(_id) == msg.sender,
            "You must own the vNFT to use this feature"
        );
        _;
    }

    modifier notLocked(uint256 _id) {
        require(!lockedAddons.contains(_id), "This addon is locked");
        _;
    }

    modifier notPaused() {
        require(!paused, "Contract paused!");
        _;
    }

    // get how many addons a pet is using
    function addonsBalanceOf(uint256 _nftId) public view returns (uint256) {
        return addonsConsumed[_nftId].length();
    }

    // get a specific addon
    function addonsOfNftByIndex(uint256 _nftId, uint256 _index)
        public
        view
        returns (uint256)
    {
        return addonsConsumed[_nftId].at(_index);
    }

    function getHp(uint256 _nftId) public view returns (uint256) {
        // A vnft need to get at least x score every two days to be healthy
        uint256 currentScore = vnft.vnftScore(_nftId);
        uint256 timeBorn = vnft.timeVnftBorn(_nftId);
        uint256 daysLived = (now.sub(timeBorn)).div(1 days);

        // multiply by healthy gem divided by 2 (every 2 days)
        uint256 expectedScore = daysLived
            .mul(healthGemScore.div(healthGemDays))
            .add(hpLostOnBattle[_nftId]);

        // get # of addons used
        uint256 addonsUsed = addonsBalanceOf(_nftId);

        if (
            !vnft.isVnftAlive(_nftId) //not dead
        ) {
            return 0;
        } else if (daysLived < 1) {
            return 70;
        }
        // here we get the % they get from score, from rarity, from used and then return based on their multiplier
        uint256 fromScore = min(currentScore.mul(100).div(expectedScore), 100);
        uint256 fromRarity = min(
            rarity[_nftId].mul(100).div(expectedRarity),
            100
        );
        uint256 fromUsed = min(addonsUsed.mul(100).div(expectedAddons), 100);
        uint256 hp = (fromRarity.mul(rarityMultiplier))
            .add(fromScore.mul(hpMultiplier))
            .add(fromUsed.mul(addonsMultiplier));

        return min(hp.div(100), 100);
    }

    function getChallenges(uint256 _nftId) public view returns (uint256) {
        if (vnft.level(_nftId) <= challengesUsed[_nftId]) {
            return 0;
        }

        return vnft.level(_nftId).sub(challengesUsed[_nftId]);
    }

    function buyAddon(uint256 _nftId, uint256 addonId)
        public
        tokenOwner(_nftId)
        notPaused
    {
        Addon storage _addon = addon[addonId];

        require(
            !addonsConsumed[_nftId].contains(addonId),
            "Pet already has this addon"
        );

        require(
            getHp(_nftId) >= _addon.requiredhp,
            "Raise your HP to buy this addon"
        );
        require(
            // @TODO double check < or <=
            _addon.used < _addon.quantity &&
                addons.balanceOf(address(this), addonId) >= 1,
            "Addon not available"
        );

        _addon.used = _addon.used.add(1);

        addonsConsumed[_nftId].add(addonId);

        rarity[_nftId] = rarity[_nftId].add(_addon.rarity);

        uint256 artistCut = _addon.price.mul(artistPct).div(100);

        muse.transferFrom(msg.sender, _addon.artistAddr, artistCut);
        muse.burnFrom(msg.sender, _addon.price.sub(artistCut));
        emit BuyAddon(_nftId, addonId, msg.sender);
    }

    function useAddon(uint256 _nftId, uint256 _addonID)
        public
        tokenOwner(_nftId)
        notPaused
    {
        require(
            !addonsConsumed[_nftId].contains(_addonID),
            "Pet already has this addon"
        );
        require(
            addons.balanceOf(msg.sender, _addonID) >= 1,
            "!own the addon to use it"
        );

        Addon storage _addon = addon[_addonID];

        require(
            getHp(_nftId) >= _addon.requiredhp,
            "Raise your HP to use this addon"
        );

        addonsConsumed[_nftId].add(_addonID);

        rarity[_nftId] = rarity[_nftId].add(_addon.rarity);

        addons.safeTransferFrom(msg.sender, address(this), _addonID, 1, "");
        emit AttachAddon(_addonID, _nftId);
    }

    function transferAddon(
        uint256 _nftId,
        uint256 _addonID,
        uint256 _toId
    ) external tokenOwner(_nftId) notLocked(_addonID) {
        Addon storage _addon = addon[_addonID];

        require(
            getHp(_toId) >= _addon.requiredhp,
            "Receiving vNFT with no enough HP"
        );
        emit RemoveAddon(_addonID, _nftId);
        emit AttachAddon(_addonID, _toId);

        addonsConsumed[_nftId].remove(_addonID);
        rarity[_nftId] = rarity[_nftId].sub(_addon.rarity);

        addonsConsumed[_toId].add(_addonID);
        rarity[_toId] = rarity[_toId].add(_addon.rarity);
    }

    function removeAddon(uint256 _nftId, uint256 _addonID)
        public
        tokenOwner(_nftId)
        notLocked(_addonID)
    {
        // maybe can take this out for gas and the .remove would throw if no addonid on user?
        require(
            addonsConsumed[_nftId].contains(_addonID),
            "Pet doesn't have this addon"
        );
        Addon storage _addon = addon[_addonID];
        rarity[_nftId] = rarity[_nftId].sub(_addon.rarity);

        addonsConsumed[_nftId].remove(_addonID);
        emit RemoveAddon(_addonID, _nftId);

        addons.safeTransferFrom(address(this), msg.sender, _addonID, 1, "");
    }

    function removeMultiple(
        uint256[] calldata nftIds,
        uint256[] calldata addonIds
    ) external {
        for (uint256 i = 0; i < addonIds.length; i++) {
            removeAddon(nftIds[i], addonIds[i]);
        }
    }

    function useMultiple(uint256[] calldata nftIds, uint256[] calldata addonIds)
        external
    {
        for (uint256 i = 0; i < addonIds.length; i++) {
            useAddon(nftIds[i], addonIds[i]);
        }
    }

    function buyMultiple(uint256[] calldata nftIds, uint256[] calldata addonIds)
        external
    {
        for (uint256 i = 0; i < addonIds.length; i++) {
            useAddon(nftIds[i], addonIds[i]);
        }
    }

    function getAttackInfo(uint256 _nftId, uint256 _opponent) public view returns (
            uint256 oponentHp,
            uint256 attackerHp,
            uint256 successPercent,
            uint256 estimatedReward
        ) {
        oponentHp = getHp(_opponent);
        attackerHp = getHp(_nftId);
        successPercent = attackerHp.mul(2).mul(100).div(oponentHp.add(attackerHp.mul(2))); // TODO JULEs manually check
        estimatedReward = vnft.level(_nftId).mul(15).div(100);
        if (estimatedReward <= 4) {
            estimatedReward = 4;
        }
    }

    // kill them all
    function battle(uint256 _nftId, uint256 _opponent)
        public
        tokenOwner(_nftId)
    {
        uint256 oponentHp = getHp(_opponent);
        uint256 attackerHp = getHp(_nftId);

        require(vnft.ownerOf(_opponent) != msg.sender, "Can't atack yourself");
        require(_nftId != _opponent, "Can't attack yourself");

        // TODO change id to battles accessory
        // require(addonsConsumed[_nftId].contains(4), "You need battles addon");

        // require x challenges and x hp or xx rarity for battles
        require(
            getChallenges(_nftId) >= 1 && attackerHp >= 70, //decide
            "can't challenge"
        );

        require(
            timesAttacked[_opponent] <= 10,
            "This pet was attacked 10 times already"
        );

        // require opponent to be of certain threshold 30?
        require(oponentHp <= 90, "You can't attack this pet");

        challengesUsed[_nftId] = challengesUsed[_nftId].add(1);
        timesAttacked[_opponent] = timesAttacked[_opponent].add(1);

        //decide winner
        uint256 loser;
        uint256 winner;

        //@TODO fix this
        // The percentage of attack is weighted between your HP and the pet HP
        // in the case where oponent as 20HP and attacker has 100
        // the chance of winning is 2 times your HP: 2*100 out of 220 (sum of both HP and attacker hp*2)
        if (
            randomNumber(_nftId, oponentHp.add(attackerHp.mul(2))) < oponentHp
        ) {
            loser = _nftId;
            winner = _opponent;
        } else {
            loser = _opponent;
            winner = _nftId;
        }

        // then do all calcs based on winner, could be opponent or nftid
        if (getHp(loser) < 20 || getHp(loser) == 5) {
            // need 6 health gem score more to to expected score
            hpLostOnBattle[loser] = hpLostOnBattle[loser].add(
                healthGemScore.mul(6)
            );
        } else if (getHp(loser) >= 20) {
            // need 3 health gem score more to to expected score
            hpLostOnBattle[loser] = hpLostOnBattle[loser].add(
                healthGemScore.mul(3)
            );
        }

        if (winner == _nftId) {
            // get 15% of level in muse
            uint256 museWon = vnft.level(winner).mul(15).div(100);
            if (museWon <= 4) {
                museWon = 4;
            }
            muse.mint(vnft.ownerOf(winner), museWon * 10**18);
        }

    }

    function cashback(uint256 _nftId) external tokenOwner(_nftId) {
        //TODO  own cahabck addon
        require(addonsConsumed[_nftId].contains(1), "You need cashback addon");
        //    have premium hp
        require(getHp(_nftId) >= premiumHp, "Raise your hp to claim cashback");
        // didn't get cashback in last 7 days
        require(
            toReceiveCashback[msg.sender] >= block.timestamp ||
                toReceiveCashback[msg.sender] == 0,
            "You can't claim cahsback yet"
        );

        toReceiveCashback[msg.sender] = block.timestamp.add(7 days);

        uint256 currentScore = vnft.vnftScore(_nftId);
        uint256 timeBorn = vnft.timeVnftBorn(_nftId);
        uint256 daysLived = (now.sub(timeBorn)).div(1 days);

        require(daysLived >= 14, "Lived at least 14 days for cashback");

        uint256 expectedScore = daysLived.mul(
            healthGemScore.div(healthGemDays)
        );

        uint256 fromScore = min(currentScore.mul(100).div(expectedScore), 100);
        console.log("fromScore: ", fromScore);

        uint256 museSpent = healthGemPrice.mul(7).mul(fromScore).div(100);
        console.log("museSpent: ", museSpent);

        uint256 cashbackAmt = museSpent.mul(cashbackPct).div(100);

        console.log("cashbackAmt: ", cashbackAmt);

        muse.mint(msg.sender, cashbackAmt);
    }

    // this is in case a dead pet addons is stuck in contract, we can use for diff cases.
    function withdraw(uint256 _id, address _to) external onlyOwner {
        addons.safeTransferFrom(address(this), _to, _id, 1, "");
    }

    function createAddon(
        string calldata _type,
        uint256 price,
        uint256 _hp,
        uint256 _rarity,
        string calldata _artistName,
        address _artist,
        uint256 _quantity,
        bool _lock
    ) external onlyOwner {
        _addonId.increment();
        uint256 newAddonId = _addonId.current();

        addon[newAddonId] = Addon(
            _type,
            price,
            _hp,
            _rarity,
            _artistName,
            _artist,
            _quantity,
            0
        );
        addons.mint(address(this), newAddonId, _quantity, "");

        if (_lock) {
            lockAddon(newAddonId);
        }

        emit CreateAddon(newAddonId, _type, _rarity, _quantity);
    }

    function createAddonAndSend(
        string calldata _type,
        uint256 _hp,
        uint256 _rarity,
        string calldata _artistName,
        address _artist,
        uint256 _quantity,
        bool _lock
    ) external onlyOwner {
        _addonId.increment();
        uint256 newAddonId = _addonId.current();

        addon[newAddonId] = Addon(
            _type,
            0,
            _hp,
            _rarity,
            _artistName,
            _artist,
            _quantity,
            _quantity //used must be set as quantity to avoid people trying to buy
        );
        addons.mint(address(msg.sender), newAddonId, _quantity, "");

        if (_lock) {
            lockAddon(newAddonId);
        }

        emit CreateAddon(newAddonId, _type, _rarity, _quantity);
    }

    function getVnftInfo(uint256 _nftId)
        public
        view
        returns (
            uint256 _vNFT,
            uint256 _rarity,
            uint256 _hp,
            uint256 _addonsCount,
            uint256[10] memory _addons
        )
    {
        _vNFT = _nftId;
        _rarity = rarity[_nftId];
        _hp = getHp(_nftId);
        _addonsCount = addonsBalanceOf(_nftId);
        uint256 index = 0; // NOT FOR @JULES THIS IS HIGHLY EXPERIMENTAL NEED TO TEST
        while (index < _addonsCount && index < 10) {
            _addons[index] = (addonsConsumed[_nftId].at(index));
            index = index + 1;
        }
    }

    function editAddon(
        uint256 _id,
        string calldata _type,
        uint256 price,
        uint256 _requiredhp,
        uint256 _rarity,
        string calldata _artistName,
        address _artist,
        uint256 _quantity,
        uint256 _used,
        bool _lock
    ) external onlyOwner {
        Addon storage _addon = addon[_id];
        _addon._type = _type;
        _addon.price = price * 10**18;
        _addon.requiredhp = _requiredhp;
        _addon.rarity = _rarity;
        _addon.artistName = _artistName;
        _addon.artistAddr = _artist;
        if (_quantity > _addon.quantity) {
            addons.mint(address(this), _id, _quantity.sub(_addon.quantity), "");
        } else if (_quantity < _addon.quantity) {
            addons.burn(address(this), _id, _addon.quantity - _quantity);
        }
        _addon.quantity = _quantity;
        _addon.used = _used;

        if (_lock) {
            lockAddon(_id);
        }

        emit EditAddon(_id, _type, price, _quantity);
    }

    function lockAddon(uint256 _id) public onlyOwner {
        lockedAddons.add(_id);
    }

    function unlockAddon(uint256 _id) public onlyOwner {
        lockedAddons.remove(_id);
    }

    function setArtistPct(uint256 _newPct) external onlyOwner {
        artistPct = _newPct;
    }

    function setHealthStrat(
        uint256 _score,
        uint256 _healthGemPrice,
        uint256 _healthGemId,
        uint256 _days,
        uint256 _hpMultiplier,
        uint256 _rarityMultiplier,
        uint256 _expectedAddons,
        uint256 _addonsMultiplier,
        uint256 _expectedRarity,
        uint256 _premiumHp,
        uint256 _cashbackPct
    ) external onlyOwner {
        healthGemScore = _score;
        healthGemPrice = _healthGemPrice;
        healthGemId = _healthGemId;
        healthGemDays = _days;
        hpMultiplier = _hpMultiplier;
        rarityMultiplier = _rarityMultiplier;
        expectedAddons = _expectedAddons;
        addonsMultiplier = _addonsMultiplier;
        expectedRarity = _expectedRarity;
        premiumHp = _premiumHp;
        cashbackPct = _cashbackPct;
    }

    function pause(bool _paused) public onlyOwner {
        paused = _paused;
    }

    function min(uint256 a, uint256 b) private pure returns (uint256) {
        return a < b ? a : b;
    }

    /* generates a number from 0 to 2^n based on the last n blocks */
    function randomNumber(uint256 seed, uint256 max)
        public
        view
        returns (uint256 _randomNumber)
    {
        uint256 n = 0;
        for (uint256 i = 0; i < 3; i++) {
            if (
                uint256(
                    keccak256(
                        abi.encodePacked(blockhash(block.number - i - 1), seed)
                    )
                ) %
                    2 ==
                0
            ) n += 2**i;
        }
        return n % max;
    }
}
