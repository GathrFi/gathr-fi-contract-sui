#[test_only]
module gathr_fi_sui::gathrfi_tests {
    use sui::test_scenario;
    use gathr_fi_sui::gathrfi::{Self, Expense, COIN};
    use sui::coin::{Self, Coin};

    #[test]
    fun test_add_expense() {
        let mut scenario = test_scenario::begin(@0x1);
        
        let amount = 100;
        let description = b"Test expense";
        let split_members = vector[@0x1, @0x2];
        let split_amounts = vector[50, 50];

        gathrfi::add_expense(
            amount, 
            description, 
            split_members, 
            split_amounts, 
            test_scenario::ctx(&mut scenario)
        );

        test_scenario::next_tx(&mut scenario, @0x1);

        let expense: Expense = test_scenario::take_shared(&scenario);
        let (
            payer, 
            expense_amount, 
            amount_settled, 
            _, 
            fully_settled
        ) = gathrfi::get_expense(&expense);

        assert!(payer == @0x1, 0);
        assert!(expense_amount == 100, 1);
        assert!(amount_settled == 50, 2);
        assert!(!fully_settled, 3);
        assert!(gathrfi::get_amount_owed(&expense, @0x1) == 0, 4);
        assert!(gathrfi::get_amount_owed(&expense, @0x2) == 50, 5);

        test_scenario::return_shared(expense);
        test_scenario::end(scenario);
    }

    #[test]
    fun test_settle_expense() {
        let mut scenario = test_scenario::begin(@0x1);

        gathrfi::add_expense(
            100, 
            b"Test expense", 
            vector[@0x1, @0x2], 
            vector[50, 50], 
            test_scenario::ctx(&mut scenario)
        );

        test_scenario::next_tx(&mut scenario, @0x2);
        {
            let coin = coin::mint_for_testing<COIN>(
                1000, 
                test_scenario::ctx(&mut scenario)
            );

            transfer::public_transfer(coin, @0x2);
        };

        test_scenario::next_tx(&mut scenario, @0x2);
        {
            let mut expense: Expense = test_scenario::take_shared(&scenario);
            let coin = test_scenario::take_from_sender<Coin<COIN>>(&scenario);
            
            let returned_coin = gathrfi::settle_expense(
                &mut expense, 
                coin, 
                test_scenario::ctx(&mut scenario)
            );

            transfer::public_transfer(returned_coin, @0x2);
            test_scenario::return_shared(expense);
        };

        test_scenario::next_tx(&mut scenario, @0x2);
        let expense: Expense = test_scenario::take_shared(&scenario);
        let (_, _, amount_settled, _, fully_settled) = gathrfi::get_expense(&expense);

        assert!(amount_settled == 100, 0);
        assert!(fully_settled, 1);
        assert!(gathrfi::get_amount_owed(&expense, @0x2) == 0, 2);
        assert!(gathrfi::has_settled(&expense, @0x2), 3);

        test_scenario::return_shared(expense);
        test_scenario::end(scenario);
    }
}
