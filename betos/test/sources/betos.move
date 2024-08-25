module betos_addr::betos {
    use aptos_framework::signer;
    use aptos_framework::vector;

    const STATUS_SCHEDULED: u8 = 0;
    const STATUS_FINISHED: u8 = 1;
    const STATUS_CANCELLED: u8 = 2;

    const OUTCOME_HOME: u8 = 0;
    const OUTCOME_DRAW: u8 = 1;
    const OUTCOME_AWAY: u8 = 2;

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
        user: &signer,
        fixture_id: u64,
        outcome: u8,
        wager: u64,
        odds: u64  // Odds are now passed when placing the bet
    ) acquires Market {
        let market = borrow_global_mut<Market>(signer::address_of(user));
        assert!(market.status == STATUS_SCHEDULED, 101);

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

    /// Allows a user to withdraw their winnings
    public entry fun withdraw_winnings(user: &signer) acquires Reward {
        let reward = borrow_global_mut<Reward>(signer::address_of(user));
        let _amount = reward.amount;  // Prefixed with underscore to suppress warning
        move_from<Reward>(signer::address_of(user));
    }

    /// Calculates the reward based on the wager and odds
    fun calculate_reward(wager: u64, odds: u64): u64 {
        (wager * odds) / 100
    }
}
