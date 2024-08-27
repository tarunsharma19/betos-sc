module betos_addr::betos {
    use aptos_framework::object::{Self, Object, ExtendRef};
    use aptos_framework::signer;
    use aptos_framework::primary_fungible_store;
    use aptos_framework::fungible_asset::{Self, FungibleStore, Metadata};
    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::aptos_coin::{Self, AptosCoin};
    use aptos_framework::account;
    use switchboard::aggregator; // For reading aggregators
    use switchboard::math;


    use std::vector;
    use std::option;
    use std::debug::print;
    use std::string::{Self, utf8};

    
    const STATUS_SCHEDULED: u8 = 0;
    const STATUS_FINISHED: u8 = 1;
    const STATUS_CANCELLED: u8 = 2;

    const EAGGREGATOR_INFO_EXISTS:u64 = 0;
    const ENO_AGGREGATOR_INFO_EXISTS:u64 = 1;

    const OUTCOME_HOME: u8 = 0;
    const OUTCOME_DRAW: u8 = 1;
    const OUTCOME_AWAY: u8 = 2;

    const ASSET_NAME: vector<u8> = b"Betos Token";
    const ASSET_SYMBOL: vector<u8> = b"BET";

    struct Market has key, store {
        admin: address,
        fixture_id: u64,
        status: u8,
        predictions: vector<Prediction>,
        expiry: u64,
    }

    struct Prediction has store, drop {
        user: address,
        fixture_id: u64,
        outcome: u8,
        wager: u64,
        odds: u64,  // Odds specific to this prediction
    }

    struct Reward has key, store, drop {
        user: address,
        amount: u64,
    }

    struct AggregatorInfo has copy, drop, store, key {
        aggregator_addr: address,
        latest_result: u128,
        latest_result_decimal: u8,
    }

    // add AggregatorInfo resource with latest value + aggregator address
    public entry fun log_aggregator_info(
        account: &signer,
        aggregator_addr: address, 
    ) {       
        assert!(!exists<AggregatorInfo>(signer::address_of(account)), EAGGREGATOR_INFO_EXISTS);

        // get latest value 
        let (value, dec, _neg) = math::unpack(aggregator::latest_value(aggregator_addr)); 
        move_to(account, AggregatorInfo {
            aggregator_addr: aggregator_addr,
            latest_result: value,
            latest_result_decimal: dec
        });
    }   

    fun init_module(deployer: &signer) {
        // Create the fungible asset metadata object. 
        let constructor_ref = &object::create_named_object(deployer, ASSET_SYMBOL);
        primary_fungible_store::create_primary_store_enabled_fungible_asset(
            constructor_ref,
            option::none(),
            utf8(ASSET_NAME), 
            utf8(ASSET_SYMBOL), 
            8, 
            utf8(b"http://example.com/favicon.ico"), 
            utf8(b"http://example.com"), 
        );
    }

    /// Creates a new betting market
    public entry fun create_market(
        admin: &signer,
        fixture_id: u64,
        expiry: u64
    ) {
        let market = Market {
            admin: signer::address_of(admin),
            fixture_id,
            status: STATUS_SCHEDULED,
            predictions: vector::empty<Prediction>(),
            expiry,
        };
        move_to(admin, market);
    }

    /// Allows a user to place a prediction on an existing market
    public entry fun place_prediction(
        admin: address,
        user: &signer,
        fixture_id: u64,
        outcome: u8,
        wager: u64,
        odds: u64  // Odds are now passed when placing the bet
    ) acquires Market {
        let market = borrow_global_mut<Market>(admin);
        assert!(market.status == STATUS_SCHEDULED, 101);

        // Verify that the user is sending the exact amount of APT as wager
        let coin = coin::withdraw<AptosCoin>(user, wager);
        coin::deposit(admin, coin);

        let prediction = Prediction {
            user: signer::address_of(user),
            fixture_id,
            outcome,
            wager,
            odds,  // Store the odds with the prediction
        };
        vector::push_back(&mut market.predictions, prediction);
    }

    /// Resolves a market and calculates rewards
    public entry fun resolve_market(
        admin: &signer,
        fixture_id: u64,
        status: u8,
        result: u8
    ) acquires Market {
        let market = borrow_global_mut<Market>(signer::address_of(admin));
        assert!(signer::address_of(admin) == market.admin, 102);
        assert!(market.status == STATUS_SCHEDULED, 103);

        market.status = status;

        if (status == STATUS_FINISHED) {
            let len = vector::length(&market.predictions);
            let i = 0;
            while (i < len) {
                let prediction = vector::borrow(&market.predictions, i);
                if (prediction.outcome == result) {
                    let reward_amount = calculate_reward(prediction.wager, prediction.odds);
                    let reward = Reward {
                        user: prediction.user,
                        amount: reward_amount,
                    };
                    move_to(admin, reward);
                };
                i = i + 1;
            }
        }
    }

    /// Distributes APT tokens as rewards
    public entry fun distribute_rewards(admin: &signer) acquires Reward {
        let admin_address = signer::address_of(admin);
        let rewards = borrow_global_mut<Reward>(admin_address);
        let reward_amount = rewards.amount;

        coin::transfer<AptosCoin>(admin, rewards.user, reward_amount);

        // Remove the reward entry
        move_from<Reward>(admin_address);
    }

    /// Allows a user to withdraw their winnings
    public entry fun withdraw_winnings(user: &signer) acquires Reward {
        let reward = borrow_global_mut<Reward>(signer::address_of(user));
        let amount = reward.amount;
        coin::transfer<AptosCoin>(user, signer::address_of(user), amount);
        move_from<Reward>(signer::address_of(user));
    }

    /// Calculates the reward based on the wager and odds
    fun calculate_reward(wager: u64, odds: u64): u64 {
        (wager * odds) / 100
    }

    
    #[test(admin = @0x123, user1 = @0x456, user2 = @0x789)]
    public entry fun test_betting_flow(admin: signer, user1: signer, user2: signer) 
    acquires 
    Market  
    // Reward
    {
        let admin_address = signer::address_of(&admin);
        let user1_address = signer::address_of(&user1);
        init_module(&admin);
        init_module(&user1);
        // Create accounts for admin, user1, and user2 for the test
        account::create_account_for_test(admin_address);
        account::create_account_for_test(user1_address);
        // account::create_account_for_test(signer::address_of(&user1));
        // account::create_account_for_test(signer::address_of(&user2));
        // aptos_coin::publish_store(&admin);
        // Initialize contract with admin account
        create_market(&admin, 1, 86400); // Market expiry set to 1 day in seconds
        //to pass our aptos coin balance assertion
        // aptos_coin::deposit(admin_address, aptos_coin::mint_apt_fa_for_test(1001));
        // aptos_coin::deposit(user1_address, aptos_coin::mint_apt_fa_for_test(1001));
        primary_fungible_store::deposit(admin_address, aptos_coin::mint_apt_fa_for_test(1001));
        primary_fungible_store::deposit(user1_address, aptos_coin::mint_apt_fa_for_test(1001));
        // aptos_coin::mint_apt_fa_for_test(amount)
        // Admin places a bet on OUTCOME_HOME
        place_prediction(
            admin_address,  // Admin's address
            &user1,                      // Admin's signer
            1,                           // Fixture ID
            OUTCOME_HOME,                // Outcome
            1,                         // Wager
            2                            // Odds
        );
        
        // User1 places a bet on OUTCOME_HOME
        // place_prediction(
        //     admin_address,  // Admin's address (same market)
        //     &user1,                      // User1's signer
        //     1,                           // Fixture ID
        //     OUTCOME_HOME,                // Outcome
        //     150,                         // Wager
        //     250                          // Odds
        // );
        
        // Fetch the market to verify the predictions
        // let market = borrow_global<Market>(admin_address);
        
        // let prediction_admin = vector::borrow(&market.predictions, 0);
        // assert!(prediction_admin.user == admin_address, 5);
        // assert!(prediction_admin.outcome == OUTCOME_HOME, 6);
        
        // let prediction_user1 = vector::borrow(&market.predictions, 1);
        // assert!(prediction_user1.user == signer::address_of(&user1), 7);
        // assert!(prediction_user1.outcome == OUTCOME_HOME, 8);
        
        // // Resolve the market with OUTCOME_HOME as the result
        // resolve_market(&admin, 1, STATUS_FINISHED, OUTCOME_HOME);
        
        // // Verify reward allocation
        // let reward_admin = borrow_global<Reward>(admin_address);
        // assert!(reward_admin.amount == 200, 11); // Admin's reward: (100 * 2) / 100 = 200
        
        // let reward_user1 = borrow_global<Reward>(signer::address_of(&user1));
        // assert!(reward_user1.amount == 375, 12); // User1's reward: (150 * 2.5) / 100 = 375
        
        // // Distribute rewards
        // distribute_rewards(&admin);

        // log_aggregator_info(&admin,0x7457731ac96b5943d01f3f1ce1fe739b53ebc5aeec45432afa169515b9f7eb1b);

        // Admin and User1 withdraw their winnings
        // withdraw_winnings(&admin);
        // withdraw_winnings(&user1);
    }
}
