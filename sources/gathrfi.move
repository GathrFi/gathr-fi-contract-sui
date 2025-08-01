module gathr_fi_sui::gathrfi {
    use sui::coin::{Self, Coin};
    use sui::event;

    const EInvalidSplit: u64 = 1;
    const EAlreadySettled: u64 = 2;
    const EExpenseFullySettled: u64 = 3;
    const EInsufficientCoin: u64 = 4;
    const EMemberNotFound: u64 = 5;

    public struct COIN has drop {}

    public struct Member has store, copy, drop {
        addr: address,
        amount_owed: u64,
        has_settled: bool,
    }

    public struct Expense has key, store {
        id: UID,
        payer: address,
        amount: u64,
        amount_settled: u64,
        description: vector<u8>,
        members: vector<Member>,
        fully_settled: bool,
    }

    public struct ExpenseAdded has copy, drop {
        expense_id: address,
        payer: address,
        amount: u64,
        description: vector<u8>,
    }

    public struct ExpenseSplit has copy, drop {
        expense_id: address,
        split_members: vector<address>,
        split_amounts: vector<u64>,
    }

    public struct ExpenseSettled has copy, drop {
        expense_id: address,
        member: address,
        amount: u64,
    }

    public fun add_expense(
        amount: u64,
        description: vector<u8>,
        split_members: vector<address>,
        split_amounts: vector<u64>,
        ctx: &mut TxContext,
    ) {
        let sender = tx_context::sender(ctx);
        let expense_id = object::new(ctx);
        let expense_addr = object::uid_to_address(&expense_id);

        assert!(vector::length(&split_members) == vector::length(&split_amounts), EInvalidSplit);

        let mut members = vector::empty<Member>();
        let mut total_split = 0;
        let mut amount_settled = 0;

        let mut i = 0;
        while (i < vector::length(&split_members)) {
            let member_addr = *vector::borrow(&split_members, i);
            let member_amount = *vector::borrow(&split_amounts, i);
            
            let is_payer = member_addr == sender;
            let member = Member {
                addr: member_addr,
                amount_owed: if (is_payer) 0 else member_amount,
                has_settled: is_payer,
            };
            
            if (is_payer) {
                amount_settled = amount_settled + member_amount;
            };
            
            vector::push_back(&mut members, member);
            total_split = total_split + member_amount;
            i = i + 1;
        };

        assert!(total_split == amount, EInvalidSplit);

        let expense = Expense {
            id: expense_id,
            payer: sender,
            amount,
            amount_settled,
            description,
            members,
            fully_settled: amount_settled == amount,
        };

        transfer::share_object(expense);

        event::emit(ExpenseAdded {
            expense_id: expense_addr,
            payer: sender,
            amount,
            description,
        });

        event::emit(ExpenseSplit {
            expense_id: expense_addr,
            split_members,
            split_amounts,
        });
    }

    public fun settle_expense(
        expense: &mut Expense,
        mut coin: Coin<COIN>,
        ctx: &mut TxContext
    ): Coin<COIN> {
        let sender = tx_context::sender(ctx);
        assert!(!expense.fully_settled, EExpenseFullySettled);

        let mut member_index = 0;
        let mut found = false;
        let members_len = vector::length(&expense.members);
        
        while (member_index < members_len) {
            let member = vector::borrow(&expense.members, member_index);
            if (member.addr == sender) {
                found = true;
                break
            };
            member_index = member_index + 1;
        };
        
        assert!(found, EMemberNotFound);
        
        let member = vector::borrow_mut(&mut expense.members, member_index);
        assert!(!member.has_settled, EAlreadySettled);
        assert!(member.amount_owed > 0, EInvalidSplit);
        
        let amount_owed = member.amount_owed;
        assert!(coin::value(&coin) >= amount_owed, EInsufficientCoin);

        let payment = coin::split(&mut coin, amount_owed, ctx);
        transfer::public_transfer(payment, expense.payer);

        member.amount_owed = 0;
        member.has_settled = true;
        expense.amount_settled = expense.amount_settled + amount_owed;

        if (expense.amount_settled == expense.amount) {
            expense.fully_settled = true;
        };

        event::emit(ExpenseSettled {
            expense_id: object::uid_to_address(&expense.id),
            member: sender,
            amount: amount_owed,
        });

        coin
    }

    public fun get_expense(expense: &Expense): (address, u64, u64, vector<u8>, bool) {
        (
            expense.payer, 
            expense.amount, 
            expense.amount_settled, 
            expense.description, 
            expense.fully_settled
        )
    }

    public fun get_amount_owed(expense: &Expense, member: address): u64 {
        let mut i = 0;
        while (i < vector::length(&expense.members)) {
            let member_data = vector::borrow(&expense.members, i);
            if (member_data.addr == member) {
                return member_data.amount_owed
            };
            i = i + 1;
        };
        0
    }

    public fun has_settled(expense: &Expense, member: address): bool {
        let mut i = 0;
        while (i < vector::length(&expense.members)) {
            let member_data = vector::borrow(&expense.members, i);
            if (member_data.addr == member) {
                return member_data.has_settled
            };
            i = i + 1;
        };
        false
    }
}
