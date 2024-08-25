module betos_addr::betos {
    // use aptos_framework::signer;
    use aptos_framework::vector;
    use std::option;
    use std::signer;

    const STATUS_SCHEDULED: u8 = 0;
    const STATUS_FINISHED: u8 = 1;
    const STATUS_CANCELLED: u8 = 2;

    const OUTCOME_HOME: u8 = 0;
    const OUTCOME_DRAW: u8 = 1;
    const OUTCOME_AWAY: u8 = 2;

    struct Market has key, store, drop {
        admin: address,
        fixture_id: u64,
        status: u8,
        odds: vector<Odds>,
        predictions: vector<Prediction>,
        expiry: u64,
    }

    struct Prediction has store, drop {
        user: address,
        fixture_id: u64,
        outcome: u8,
        wager: u64,
        odds: vector<Odds>,
    }

    struct Odds has store, copy, drop {
        outcome: u8,
        value: u64,
    }

    struct Reward has key, store, drop {
        user: address,
        amount: u64,
    }

    public entry fun create_market(
        admin: &signer,
        fixture_id: u64,
        odds: vector<Odds>,
        expiry: u64
    ) {
        let market = Market {
            admin: signer::address_of(admin),
            fixture_id,
            status: STATUS_SCHEDULED,
            odds,
            predictions: vector::empty<Prediction>(),
            expiry,
        };
        move_to(admin, market);
    }

    public entry fun place_prediction(
        user: &signer,
        fixture_id: u64,
        outcome: u8,
        wager: u64,
        odds: vector<Odds>
    ) {
        let market = borrow_global_mut<Market>(signer::address_of(user));
        assert!(market.status == STATUS_SCHEDULED, 1);
        let prediction = Prediction {
            user: signer::address_of(user),
            fixture_id,
            outcome,
            wager,
            odds,
        };
        vector::push_back(&mut market.predictions, prediction);
    }

    public entry fun resolve_market(
        admin: &signer,
        fixture_id: u64,
        status: u8,
        result: u8
    ) {
        let market = borrow_global_mut<Market>(signer::address_of(admin));
        assert!(signer::address_of(admin) == market.admin, 2);
        market.status = status;

        if (status == STATUS_FINISHED) {
            let len = vector::length(&market.predictions);
            let total_wager: u64 = 0;

            let i: u64 = 0;
            while (i < len) {
                let prediction = vector::borrow(&market.predictions, i);
                total_wager = total_wager + prediction.wager;
                i = i + 1;
            };

            let j: u64 = 0;
            while (j < len) {
                let prediction = vector::borrow(&market.predictions, j);
                if (prediction.outcome == result) {
                    let odds_value = find_odds(&market.odds, result);
                    let reward_amount = calculate_reward(prediction.wager, odds_value);
                    let reward = Reward {
                        user: prediction.user,
                        amount: reward_amount,
                    };
                    move_to(&signer::address_of(admin), reward);
                };
                j = j + 1;
            }
        }
    }

    public entry fun withdraw_winnings(user: &signer) {
        let reward = borrow_global_mut<Reward>(signer::address_of(user));
        let amount = reward.amount;
        // Code to transfer the amount to user's wallet would go here
        move_from<Reward>(signer::address_of(user));
    }

    public fun get_market_info(fixture_id: u64): (u8, vector<Odds>, u64) {
        let market = borrow_global<Market>(signer::address_of(user));
        (market.status, market.odds, market.expiry)
    }

    public entry fun cancel_prediction(user: &signer, fixture_id: u64) {
        let market = borrow_global_mut<Market>(signer::address_of(user));
        assert!(market.status == STATUS_SCHEDULED, 3);

        let len = vector::length(&market.predictions);
        let i = 0;
        while (i < len) {
            let prediction = vector::borrow(&market.predictions, i);
            if (prediction.user == signer::address_of(user)) {
                vector::remove(&mut market.predictions, i);
                break;
            };
            i = i + 1;
        }
    }

    public entry fun check_balance(user: &signer): u64 {
        let reward = borrow_global<Reward>(signer::address_of(user));
        reward.amount
    }

    fun find_odds(odds: &vector<Odds>, outcome: u8): u64 {
        let len = vector::length(odds);
        let i = 0;
        while (i < len) {
            let o = vector::borrow(odds, i);
            if (o.outcome == outcome) {
                return o.value;
            };
            i = i + 1;
        };
        0
    }

    fun calculate_reward(wager: u64, odds: u64): u64 {
        (wager * odds) / 100
    }
}
