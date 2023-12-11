mod packing;
mod tests;
mod tokens;

#[starknet::interface]
trait IMarket<TContractState> {
    fn create(ref self: TContractState, token_id: u32, collection_id: u16, price: u128, expiration: u64,);
    fn accept(ref self: TContractState, order_id: felt252);
    fn cancel(ref self: TContractState, order_id: felt252);
    fn edit(ref self: TContractState, order_id: felt252, new_price: u128);
    fn whitelist_collection(ref self: TContractState, collection_address: core::starknet::ContractAddress);
    fn update_market_fee(ref self: TContractState, fee: felt252);
    fn update_market_owner_address(ref self: TContractState, new_address: core::starknet::ContractAddress);
    fn view_order(ref self: TContractState, order_id: felt252) -> marketplace::packing::MarketOrder;
    fn pause(ref self: TContractState);
    fn unpause(ref self: TContractState);
}

#[starknet::contract]
mod Market {
    use core::zeroable::Zeroable;
    use marketplace::packing::MarketOrder;

    use openzeppelin::token::erc20::interface::{
        IERC20Dispatcher, IERC20DispatcherImpl, IERC20CamelDispatcher, IERC20CamelDispatcherTrait
    };

    use openzeppelin::token::erc721::interface::{IERC721Dispatcher, IERC721DispatcherTrait,};

    use starknet::{get_caller_address, ContractAddress, get_block_timestamp, get_contract_address};
    use super::IMarket;

    #[derive(Drop, Copy, Serde)]
    enum OrderState {
        Created,
        Edited,
        Cancelled,
        Accepted,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        OrderEvent: OrderEvent,
    }

    #[derive(Drop, starknet::Event)]
    struct OrderEvent {
        market_order: MarketOrder,
        order_id: felt252,
        state: OrderState,
    }

    #[storage]
    struct Storage {
        market_order: LegacyMap::<felt252, MarketOrder>, // order
        order_count: felt252,
        collection_address: LegacyMap::<u16, IERC721Dispatcher>, // collection addresses
        collection_count: u16,
        fee_token: IERC20Dispatcher,
        market_fee: felt252,
        market_owner_address: ContractAddress,
        paused: bool,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState, fee_token_address: ContractAddress, fee: felt252, market_owner_address: ContractAddress
    ) {
        self.fee_token.write(IERC20Dispatcher { contract_address: fee_token_address });
        self.market_fee.write(fee);
        self.market_owner_address.write(market_owner_address);
    }

    // Pauses the accept order function, in the event of a bug or exploit.
    #[inline(always)]
    fn assert_not_paused(self: @ContractState) {
        assert(!self.paused.read(), 'MARKET: paused');
    }

    #[inline(always)]
    fn assert_order_active(order: MarketOrder) {
        assert(order.active, 'MARKET: order not active');
    }

    // Checks if the caller is the DAO multisig.
    #[inline(always)]
    fn assert_only_market_owner(self: @ContractState) {
        assert(self.market_owner_address.read() == get_caller_address(), 'MARKET: caller not owner');
    }

    // Checks if the caller is the order owner.
    #[inline(always)]
    fn assert_only_market_order_owner(self: @ContractState, order: MarketOrder) {
        assert(order.owner == get_caller_address(), 'MARKET: caller not order owner');
    }

    #[abi(embed_v0)]
    impl Market of IMarket<ContractState> {
        // =========================
        // === MARKET FUNCTIONS ====
        // =========================

        /// Creates a new market order.
        /// This function checks if the collection is whitelisted, checks market is approved and then
        /// increments the order count, sets the market order in state, and emits an OrderEvent.
        /// # Arguments
        /// * `market_order` - The market order to be created.
        fn create(ref self: ContractState, token_id: u32, collection_id: u16, price: u128, expiration: u64,) {
            // create market order
            let caller = get_caller_address();
            let market_order = MarketOrder { owner: caller, token_id, collection_id, price, expiration, active: true };
            let collection_dispatcher = self.collection_address.read(market_order.collection_id);

            // assert collection is whitelisted
            // @dev: collections need to be whitelisted
            assert(collection_dispatcher.contract_address.is_non_zero(), 'MARKET: Not whitelisted');

            // assert market is approved
            // @dev: a tx should be sent before calling this authorizing the contract to transfer the NFT
            assert(collection_dispatcher.is_approved_for_all(caller, get_contract_address()), 'MARKET: Not approved');

            // assert expiration is in the future and at least 1 day
            assert(market_order.expiration > get_block_timestamp() + 86400, 'MARKET: Not in future');

            // assert owner of NFT is caller
            assert(collection_dispatcher.owner_of(market_order.token_id.into()) == caller, 'MARKET: Not owner');

            // increment
            let count = self.order_count.read() + 1;

            // set market order // set count // set owner of bounty
            self.market_order.write(count, market_order);
            self.order_count.write(count);

            // emit event
            self.emit(OrderEvent { market_order, order_id: count, state: OrderState::Created });
        }

        /// Accepts a market order.
        /// Retrieves the order, transfers the required tokens and NFTs, sets the order to inactive, and emits an OrderEvent.
        /// # Arguments
        /// * `order_id` - The identifier of the order to accept.
        fn accept(ref self: ContractState, order_id: felt252) {
            // assert not paused
            assert_not_paused(@self);

            // get order
            let mut market_order = self.market_order.read(order_id);

            // assert expiration
            assert(market_order.expiration > get_block_timestamp(), 'MARKET: Expired');

            // assert active
            assert_order_active(market_order);

            let caller = get_caller_address();

            // calculate cost minus fee
            let cost = market_order.price.into();
            let fee: u256 = cost * self.market_fee.read().into() / 10000;

            // LORDS: transfer fee to owner
            self.fee_token.read().transfer_from(caller, self.market_owner_address.read(), fee.into());

            // LORDS: transfer cost minus fee from buyer to seller
            self.fee_token.read().transfer_from(caller, market_order.owner, (cost.into() - fee).into());

            // NFT: from seller to buyer
            self
                .collection_address
                .read(market_order.collection_id)
                .transfer_from(market_order.owner, caller, market_order.token_id.into());

            // set inactive
            market_order.active = false;
            self.market_order.write(order_id, market_order);

            // emit event
            self.emit(OrderEvent { market_order, order_id, state: OrderState::Accepted  });
        }

        /// Cancels a market order.
        /// Checks if the order is active and if the caller is the order owner, revokes approval, sets the order to inactive, and emits an OrderEvent.
        /// # Arguments
        /// * `order_id` - The identifier of the order to cancel.
        fn cancel(ref self: ContractState, order_id: felt252) {
            // get order
            let mut market_order = self.market_order.read(order_id);

            // assert active
            assert_order_active(market_order);

            // assert owner
            assert_only_market_order_owner(@self, market_order);

            // set inactive
            market_order.active = false;
            self.market_order.write(order_id, market_order);

            // emit event
            self.emit(OrderEvent { market_order, order_id, state: OrderState::Cancelled });
        }

        /// Edits an existing market order.
        /// Checks if the order is active and if the caller is the order owner, then updates the order in state and emits an OrderEvent.
        /// # Arguments
        /// * `order_id` - The identifier of the order to edit.
        fn edit(ref self: ContractState, order_id: felt252, new_price: u128) {
            // get order
            let mut market_order = self.market_order.read(order_id);

            // assert active
            assert_order_active(market_order);

            // assert owner
            assert_only_market_order_owner(@self, market_order);

            // update price
            market_order.price = new_price;
            self.market_order.write(order_id, market_order);

            // emit event
            self.emit(OrderEvent { market_order, order_id, state: OrderState::Edited  });

        }

        // =========================
        // ====== VIEW FUNCTIONS ===
        // =========================

        /// Returns a market order.
        /// # Arguments
        /// * `order_id` - The identifier of the order to view.
        fn view_order(ref self: ContractState, order_id: felt252) -> MarketOrder {
            self.market_order.read(order_id)
        }

        // =========================
        // ====== ADMIN FUNCTIONS ==
        // =========================

        // Whitelists a collection. Can only be called by the DAO multisig.
        /// # Arguments
        /// * `collection_address` - The address of the collection to whitelist.
        fn whitelist_collection(ref self: ContractState, collection_address: ContractAddress) {
            assert_only_market_owner(@self);

            // increment
            let count = self.collection_count.read() + 1;

            // set count // set owner of bounty
            self.collection_address.write(count, IERC721Dispatcher { contract_address: collection_address });
            self.collection_count.write(count);
        }

        /// Updates the DAO fee. Can only be called by the DAO multisig.
        /// # Arguments
        /// * `fee` - The new fee.
        fn update_market_fee(ref self: ContractState, fee: felt252) {
            assert_only_market_owner(@self);
            self.market_fee.write(fee);
        }

        /// Updates the DAO address. Can only be called by the DAO multisig.
        /// # Arguments
        /// * `new_address` - The new DAO address.
        fn update_market_owner_address(ref self: ContractState, new_address: ContractAddress) {
            assert_only_market_owner(@self);
            self.market_owner_address.write(new_address);
        }

        /// Pauses the contract. Can only be called by the DAO multisig
        fn pause(ref self: ContractState) {
            assert_only_market_owner(@self);
            self.paused.write(true);
        }

        /// Unpauses the contract. Can only be called by the DAO multisig
        fn unpause(ref self: ContractState) {
            assert_only_market_owner(@self);
            self.paused.write(false);
        }
    }
}
