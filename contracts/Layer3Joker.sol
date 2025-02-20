// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract Layer3Joker is Initializable, UUPSUpgradeable, ERC20Upgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {

    uint256 public constant TOTAL_SUPPLY = 333_333_333_333 * 10 ** 18;
    uint256 public totalStaked;
    uint256 public currentPrice; 
    uint256 public totalTokensSold;
    address public treasuryWallet;
	bool public tradingEnabled = true; 
   



    struct PriceTier {
        uint256 tokensSold;
        uint256 price;
    }

    struct Stake {
        uint256 amount;
        uint256 startTime;
        uint256 lockTime;
        bool active;
        bool earlyBird;
    }



   struct Proposal {
        uint256 id;
        string description;
        uint256 voteStartTime;
        uint256 voteEndTime;
        uint256 forVotes;
        uint256 againstVotes;
        bool executed;
        address proposer;
        mapping(address => bool) hasVoted;
    }
	
	uint256 public proposalCount;
    mapping(uint256 => Proposal) public proposals;
    mapping(address => uint256) public lastVoteSnapshot; // Snapshot of voting power
	mapping(address => bool) public isWhitelisted;  // Optional: Allow early trading for certain addresses


    event ProposalCreated(uint256 proposalId, string description, uint256 voteEndTime);
    event Voted(address indexed voter, uint256 proposalId, bool support, uint256 votingPower);
    event ProposalExecuted(uint256 proposalId);

    modifier onlyTokenHolders() {
        require(balanceOf(msg.sender) > 0, "Only token holders can propose");
        _;
    }

    PriceTier[] public priceTiers;
    
    mapping(address => uint256) public referralRewards;
    mapping(address => Stake) public stakes;
	mapping(address => bool) public isBlacklisted;


    event Staked(address indexed user, uint256 amount, uint256 lockTime);
    event Unstaked(address indexed user, uint256 amount, uint256 reward);
    event ReferralReward(address indexed referrer, uint256 reward);
	event PriceTiersUpdated(uint256 length, uint256 newPrice);
	event TradingEnabled(bool enabled);


    event TreasuryWalletUpdated(address newTreasuryWallet);
    event OwnerAddressUpdated(address newOwner);
    

  function initialize(address _treasuryWallet, address _owner) public initializer {
        require(_treasuryWallet != address(0), "Treasury wallet required");
        require(_owner != address(0), "Owner address required");
        __ERC20_init("Layer3 Joker", "L3M");
        __Ownable_init(_owner);
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();
        __Pausable_init();
        tradingEnabled = true;
        emit TradingEnabled(true);
        treasuryWallet = _treasuryWallet;
        

        _mint(msg.sender, TOTAL_SUPPLY);
        priceTiers.push(PriceTier({tokensSold: 100_000_000_000 * 10 ** decimals(), price: 0.00000003 ether}));
        priceTiers.push(PriceTier({tokensSold: 333_000_000_000 * 10 ** decimals(), price: 0.00000005 ether}));
        priceTiers.push(PriceTier({tokensSold: 333_333_333_333 * 10 ** decimals(), price: 0.00000007 ether})); 
        currentPrice = priceTiers[0].price;
    }
	

    function updatePrice() internal {
        for (uint256 i = 0; i < priceTiers.length; i++) {
            if (totalTokensSold <= priceTiers[i].tokensSold) {
                currentPrice = priceTiers[i].price;
                return;
            }
        }
    }

    function claimReferralRewards() external nonReentrant {
	    require(!isBlacklisted[msg.sender], "Blacklisted addresses cannot claim rewards");
        uint256 reward = referralRewards[msg.sender];
        require(reward > 0, "No referral rewards to claim");

        referralRewards[msg.sender] = 0;
        _transfer(owner(), msg.sender, reward);
    }

   function buyTokens(address referrer) external payable nonReentrant whenNotPaused {
		require(!isBlacklisted[msg.sender], "You are blacklisted from buying tokens");
		require(msg.value > 0, "No ETH sent");
		require(currentPrice > 0, "Token price is not set");

		uint256 tokensToBuy = (msg.value * (10 ** decimals())) / currentPrice;

		uint256 referralBonusPercentage = 0;
		if (tokensToBuy >= 1 * 10**18 && tokensToBuy <= 333_000_000 * 10**18) {
			referralBonusPercentage = 5;
		} else if (tokensToBuy > 333_000_000 * 10**18 && tokensToBuy <= 1_665_000_000 * 10**18) {
			referralBonusPercentage = 7;
		} else if (tokensToBuy > 1_665_000_000 * 10**18) {
			referralBonusPercentage = 10;
		}

		uint256 referralBonus = (tokensToBuy * referralBonusPercentage) / 100;

		require(balanceOf(owner()) >= tokensToBuy + referralBonus, "Not enough tokens available");

		if (referrer != address(0) && referrer != msg.sender) {
			referralRewards[referrer] += referralBonus;
			emit ReferralReward(referrer, referralBonus);
		}

		_transfer(owner(), msg.sender, tokensToBuy);
		totalTokensSold += tokensToBuy;
		updatePrice();

		payable(treasuryWallet).transfer(msg.value);
	}

    



    function stakeTokens(uint256 amount, uint256 lockTime) external nonReentrant {
	    require(!isBlacklisted[msg.sender], "Blacklisted addresses cannot stake");
        require( 
            lockTime == 1 || lockTime ==  6 || lockTime == 12 || lockTime == 18, 
            "Invalid lock period"
        );
        require(amount > 0, "Cannot stake zero tokens");
        require(balanceOf(msg.sender) >= amount, "Insufficient balance");

        uint256 lockDuration;

      
        lockDuration = lockTime * 30 days;
        
        
        _transfer(msg.sender, address(this), amount);

        bool isEarlyBird = totalTokensSold < (TOTAL_SUPPLY * 7) / 100;

        stakes[msg.sender] = Stake(amount, block.timestamp, block.timestamp + lockDuration, true, isEarlyBird);

        totalStaked += amount; // Update total staked
        emit Staked(msg.sender, amount, lockTime);
    }



    function unstakeTokens() external nonReentrant {
		Stake storage userStake = stakes[msg.sender];
		_requireActiveStake(msg.sender);
        require(block.timestamp >= userStake.lockTime, "Stake is locked");
		uint256 bonusPercentage = userStake.earlyBird ? 15 : 0;

		uint256 timeDifference = userStake.lockTime - userStake.startTime;
		uint256 daysStaked = timeDifference / 86400;
		uint256 monthStaked = daysStaked / 30;
		uint256 mohthlyBonus = 10;
		if(monthStaked ==  6){
			mohthlyBonus = 10;
		}else if(monthStaked ==  12){
			mohthlyBonus = 15;
		}else if(monthStaked >  12){
			mohthlyBonus = 20;
		}

		bonusPercentage = bonusPercentage+mohthlyBonus;

		uint256 bonusReward = (userStake.amount * bonusPercentage) / 100;
		uint256 totalReward = bonusReward;
		uint256 totalAmount = userStake.amount + totalReward;
		require(balanceOf(address(this)) >= totalAmount, "Insufficient contract balance");

		// Update user state
		userStake.active = false;
		totalStaked -= userStake.amount;

		// Perform transfer
		_transfer(address(this), msg.sender, totalAmount);

		// Emit unstake event
		emit Unstaked(msg.sender, userStake.amount, totalReward);
	}


    


   	function _update(address from, address to, uint256 amount) internal override {
        require(!isBlacklisted[from], "Sender is blacklisted");
		require(!isBlacklisted[to], "Recipient is blacklisted");
		require(tradingEnabled || isWhitelisted[from] || isWhitelisted[to], "Trading is not enabled yet");

        super._update(from, to, amount);
    }

    /**
     * @dev Set the treasury wallet (onlyOwner)
     */
    function setTreasuryWallet(address _treasuryWallet) external onlyOwner {
        require(_treasuryWallet != address(0), "Invalid treasury wallet");
        treasuryWallet = _treasuryWallet;
        emit TreasuryWalletUpdated(_treasuryWallet);
    }

    /**
     * @dev Set the new owner address (onlyOwner)
     */
    function setOwnerAddress(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Invalid owner address");
        transferOwnership(newOwner);
        emit OwnerAddressUpdated(newOwner);
    }
	
	function blacklistAddress(address account) external onlyOwner {
		require(!isBlacklisted[account], "Address is already blacklisted");
		isBlacklisted[account] = true;
	}

	function removeBlacklist(address account) external onlyOwner {
		require(isBlacklisted[account], "Address is not blacklisted");
		isBlacklisted[account] = false;
	}


    function checkRewardTillDay(address user) public view returns (uint256) {
        Stake storage userStake = stakes[user];

      _requireActiveStake(user);  


        uint256 bonusPercentage = userStake.earlyBird ? 15 : 0;
        uint256 timeElapsed = block.timestamp - userStake.startTime;
        uint256 daysLapsed = timeElapsed / 86400;
        

        uint256 timeDifference = userStake.lockTime - userStake.startTime;
        uint256 daysStaked = timeDifference / 86400;
        uint256 monthStaked = daysStaked / 30;
        uint256 monthlyBonus = 10;
        if(monthStaked ==  6){
            monthlyBonus = 10;
        }else if(monthStaked ==  12){
            monthlyBonus = 15;
        }else if(monthStaked >  12){
            monthlyBonus = 20;
        }

        bonusPercentage = bonusPercentage + monthlyBonus;
        uint256 bonusReward = (userStake.amount * bonusPercentage) / 100;
        uint256 totalReward = (bonusReward/daysStaked)  * daysLapsed;
        return totalReward;
    }


	
	function seizeBlacklistedFunds(address blacklistedUser) external onlyOwner {
		require(isBlacklisted[blacklistedUser], "User is not blacklisted");
		
		Stake storage userStake = stakes[blacklistedUser];
		_requireActiveStake(blacklistedUser);


		uint256 totalAmount = userStake.amount;
		userStake.active = false;
		totalStaked -= userStake.amount;
		
		// Move funds to the treasury wallet
		_transfer(address(this), treasuryWallet, totalAmount);

		emit Unstaked(blacklistedUser, userStake.amount, 0);
	}

    function getEthRequired(uint256 tokenAmount) public view returns (uint256 ethRequired) {
        require(currentPrice > 0, "Token price is not set");
        return (tokenAmount * currentPrice) / (10 ** decimals());
    }


    function getTokensForEth(uint256 ethAmount) public view returns (uint256 tokens) {
        require(currentPrice > 0, "Token price is not set");
        return (ethAmount * (10 ** decimals())) / currentPrice;
    }



    function _requireActiveStake(address user) internal view {
        require(stakes[user].active, "No active stake");
    }



    function vote(uint256 proposalId, bool support) external {
        Proposal storage proposal = proposals[proposalId];

        require(block.timestamp >= proposal.voteStartTime, "Voting not started");
        require(block.timestamp <= proposal.voteEndTime, "Voting ended");
        require(!proposal.hasVoted[msg.sender], "Already voted");
        
        uint256 votingPower = lastVoteSnapshot[msg.sender];
        require(votingPower > 0, "No voting power");

        if (support) {
            proposal.forVotes += votingPower;
        } else {
            proposal.againstVotes += votingPower;
        }

        proposal.hasVoted[msg.sender] = true;

        emit Voted(msg.sender, proposalId, support, votingPower);
    }

	function createProposal(string memory description, uint256 duration) external onlyTokenHolders {
        require(duration > 0, "Invalid duration");
        
        proposalCount++;
        Proposal storage newProposal = proposals[proposalCount];
        newProposal.id = proposalCount;
        newProposal.description = description;
        newProposal.voteStartTime = block.timestamp;
        newProposal.voteEndTime = block.timestamp + duration;
        newProposal.proposer = msg.sender;
        
        lastVoteSnapshot[msg.sender] = balanceOf(msg.sender);

        emit ProposalCreated(proposalCount, description, newProposal.voteEndTime);
    }

    function executeProposal(uint256 proposalId) external onlyOwner {
        Proposal storage proposal = proposals[proposalId];

        require(block.timestamp > proposal.voteEndTime, "Voting still ongoing");
        require(!proposal.executed, "Proposal already executed");

        if (proposal.forVotes > proposal.againstVotes) {
            // Proposal is accepted; Execute logic (adjust staking/referral/price tiers)
            proposal.executed = true;

            emit ProposalExecuted(proposalId);
        }
    }

	function setTradingEnabled(bool _enabled) external onlyOwner {
		tradingEnabled = _enabled;
		emit TradingEnabled(_enabled);
	}

	function whitelistAddress(address _user, bool _status) external onlyOwner {
		isWhitelisted[_user] = _status;
	}

  

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}