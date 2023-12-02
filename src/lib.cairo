mod packing;
mod tests;
mod tokens;

#[starknet::interface]
trait IMarket<TContractState> {
    fn create(
        ref self: TContractState, token_id: u32, collection_id: u16, price: u128, expiration: u64,
    );
    fn accept(ref self: TContractState, order_id: felt252);
    fn cancel(ref self: TContractState, order_id: felt252);
    fn edit(ref self: TContractState, order_id: felt252, new_price: u128);
    fn whitelist_collection(
        ref self: TContractState, collection_address: core::starknet::ContractAddress
    );
    fn update_owner_fee(ref self: TContractState, fee: felt252);
    fn update_owner_address(ref self: TContractState, new_address: core::starknet::ContractAddress);
    fn view_order(ref self: TContractState, order_id: felt252) -> marketplace::packing::MarketOrder;
    fn pause(ref self: TContractState);
    fn unpause(ref self: TContractState);
}

#[starknet::contract]
mod Market {
    use core::debug::PrintTrait;
    use super::IMarket;
    use marketplace::packing::{MarketOrderTrait, MarketOrder, ORDER_STATE};

    use core::{
        starknet::{
            get_caller_address, ContractAddress, get_block_timestamp, info::BlockInfo,
            get_contract_address
        },
    };

    use openzeppelin::token::erc20::interface::{
        IERC20Dispatcher, IERC20DispatcherImpl, IERC20Camel, IERC20CamelDispatcher,
        IERC20CamelDispatcherTrait, IERC20CamelLibraryDispatcher
    };

    use openzeppelin::token::erc721::interface::{
        IERC721Dispatcher, IERC721DispatcherTrait, IERC721LibraryDispatcher
    };

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        OrderEvent: OrderEvent,
    }

    #[derive(Drop, starknet::Event)]
    struct OrderEvent {
        market_order: MarketOrder,
        timestamp: u64,
    }

    #[storage]
    struct Storage {
        market_order: LegacyMap::<felt252, MarketOrder>, // order
        owner: LegacyMap::<felt252, ContractAddress>, // owner of order
        order_count: felt252,
        collection_address: LegacyMap::<felt252, ContractAddress>, // collection addresses
        collection_count: felt252,
        erc_address: ContractAddress,
        owner_fee: felt252,
        owner_address: ContractAddress,
        paused: bool,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        _erc20_address: ContractAddress,
        _fee: felt252,
        _owner_address: ContractAddress
    ) {
        self.erc_address.write(_erc20_address);
        self.owner_fee.write(_fee);
        self.owner_address.write(_owner_address);
        self.paused.write(false);
    }

    // Pauses the accept order function, in the event of a bug or exploit.
    fn assert_not_paused(self: @ContractState) {
        assert(!self.paused.read(), 'MARKET: paused');
    }

    // Checks if the caller is the DAO multisig.
    fn assert_only_market_owner(self: @ContractState) {
        assert(self.owner_address.read() == get_caller_address(), 'MARKET: caller not owner');
    }

    // Checks if the caller is the order owner.
    fn assert_only_market_order_owner(self: @ContractState, order_id: felt252) {
        assert(self.owner.read(order_id) == get_caller_address(), 'MARKET: caller not order owner');
    }

    fn erc20_dispatcher(self: @ContractState) -> IERC20Dispatcher {
        IERC20Dispatcher { contract_address: self.erc_address.read(), }
    }

    fn erc721_dispatcher(self: @ContractState, collection_id: felt252) -> IERC721Dispatcher {
        IERC721Dispatcher { contract_address: self.collection_address.read(collection_id), }
    }

    #[external(v0)]
    impl Market of IMarket<ContractState> {
        // =========================
        // === MARKET FUNCTIONS ====
        // =========================

        /// Creates a new market order.
        /// This function checks if the collection is whitelisted, checks market is approved and then
        /// increments the order count, sets the market order in state, and emits an OrderEvent.
        /// # Arguments
        /// * `market_order` - The market order to be created.
        fn create(
            ref self: ContractState,
            token_id: u32,
            collection_id: u16,
            price: u128,
            expiration: u64,
        ) {
            // create market order
            let market_order = MarketOrder {
                token_id: token_id,
                collection_id: collection_id,
                price: price,
                expiration: expiration,
                active: ORDER_STATE::ACTIVE,
            };

            // assert collection is whitelisted
            // @dev: collections need to be whitelisted
            assert(
                self.collection_address.read(market_order.collection_id.into()).into() != 0,
                'MARKET: Not whitelisted'
            );

            // assert market is approved
            // @dev: a tx should be sent before calling this authorizing the contract to transfer the NFT
            assert(
                erc721_dispatcher(@self, market_order.collection_id.into())
                    .is_approved_for_all(get_caller_address(), get_contract_address()),
                'MARKET: Not approved'
            );

            // assert expiration is in the future and at least 1 day
            assert(
                market_order.expiration > get_block_timestamp() + 86400, 'MARKET: Not in future'
            );

            // assert owner of NFT is caller
            assert(
                erc721_dispatcher(@self, market_order.collection_id.into())
                    .owner_of(market_order.token_id.into()) == get_caller_address(),
                'MARKET: Not owner'
            );

            // increment
            let mut count = self.order_count.read();
            count += 1;

            // set market order // set count // set owner of bounty
            self.market_order.write(count, market_order);
            self.order_count.write(count);
            self.owner.write(count, get_caller_address());

            // emit event
            self.emit(OrderEvent { market_order, timestamp: get_block_timestamp() });
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

            // get owner
            let order_owner = self.owner.read(order_id);

            // we assert here - as the buyer can revoke approval at any time
            // asserting here means the trade will fail if the buyer has revoked approval
            // the trade should be removed from the indexer if revert happens
            assert(
                erc721_dispatcher(@self, market_order.collection_id.into())
                    .is_approved_for_all(order_owner, get_contract_address()),
                'MARKET: Not approved'
            );

            // assert expiration    
            assert(market_order.expiration > get_block_timestamp(), 'MARKET: Expired');

            // assert active
            market_order.is_active();

            // calculate cost minus fee
            let cost = market_order.price.into();
            let fee: u256 = cost * self.owner_fee.read().into() / 10000;

            // LORDS: transfer fee to owner
            erc20_dispatcher(@self)
                .transfer_from(get_caller_address(), self.owner_address.read(), fee.into());

            // LORDS: transfer cost minus fee from buyer to seller
            erc20_dispatcher(@self)
                .transfer_from(get_caller_address(), order_owner, (cost.into() - fee).into());

            // NFT: from seller to buyer
            erc721_dispatcher(@self, market_order.collection_id.into())
                .transfer_from(order_owner, get_caller_address(), market_order.token_id.into());

            // set inactive
            market_order.set_inactive();
            self.market_order.write(order_id, market_order);

            // emit event
            self.emit(OrderEvent { market_order, timestamp: get_block_timestamp() });
        }

        /// Cancels a market order.
        /// Checks if the order is active and if the caller is the order owner, revokes approval, sets the order to inactive, and emits an OrderEvent.
        /// # Arguments
        /// * `order_id` - The identifier of the order to cancel.
        fn cancel(ref self: ContractState, order_id: felt252) {
            // get order
            let mut market_order = self.market_order.read(order_id);

            // assert active
            market_order.is_active();

            // assert owner
            assert_only_market_order_owner(@self, order_id);

            // set inactive
            market_order.set_inactive();
            self.market_order.write(order_id, market_order);

            // emit event
            self.emit(OrderEvent { market_order, timestamp: get_block_timestamp() });
        }

        /// Edits an existing market order.
        /// Checks if the order is active and if the caller is the order owner, then updates the order in state and emits an OrderEvent.
        /// # Arguments
        /// * `order_id` - The identifier of the order to edit.
        fn edit(ref self: ContractState, order_id: felt252, new_price: u128) {
            // get order
            let mut market_order = self.market_order.read(order_id);

            // assert active
            market_order.is_active();

            // assert owner
            assert_only_market_order_owner(@self, order_id);

            // update price
            market_order.price = new_price;
            self.market_order.write(order_id, market_order);

            // emit event
            self.emit(OrderEvent { market_order: market_order, timestamp: get_block_timestamp() });
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
            let mut count = self.collection_count.read();
            count += 1;

            // set count // set owner of bounty
            self.collection_address.write(count, collection_address);
            self.collection_count.write(count);
        }

        /// Updates the DAO fee. Can only be called by the DAO multisig.
        /// # Arguments
        /// * `fee` - The new fee.
        fn update_owner_fee(ref self: ContractState, fee: felt252) {
            assert_only_market_owner(@self);
            self.owner_fee.write(fee);
        }

        /// Updates the DAO address. Can only be called by the DAO multisig.
        /// # Arguments
        /// * `new_address` - The new DAO address.
        fn update_owner_address(ref self: ContractState, new_address: ContractAddress) {
            assert_only_market_owner(@self);
            self.owner_address.write(new_address);
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
