mod packing;

use marketplace::packing::MarketOrder;

#[starknet::interface]
trait IMarket<TContractState> {
    fn create(ref self: TContractState, market_order: MarketOrder);
    fn accept(ref self: TContractState, order_id: felt252);
    fn cancel(ref self: TContractState, order_id: felt252);
    fn edit(ref self: TContractState, order_id: felt252);
    fn whitelist_collection(
        ref self: TContractState, collection_address: core::starknet::ContractAddress
    );
    fn update_dao_fee(ref self: TContractState, fee: felt252);
}

#[starknet::contract]
mod Market {
    use super::IMarket;

    use marketplace::packing::MarketOrderTrait;
    use marketplace::packing::{MarketOrder, ORDER_STATE};

    use core::{
        array::{SpanTrait, ArrayTrait}, integer::u256_try_as_non_zero, traits::{TryInto, Into},
        clone::Clone, poseidon::poseidon_hash_span, option::OptionTrait, box::BoxTrait,
        starknet::{
            get_caller_address, ContractAddress, ContractAddressIntoFelt252, contract_address_const,
            get_block_timestamp, info::BlockInfo, get_contract_address
        },
    };

    use openzeppelin::token::erc20::erc20::ERC20;
    use openzeppelin::token::erc20::interface::{
        IERC20Camel, IERC20CamelDispatcher, IERC20CamelDispatcherTrait, IERC20CamelLibraryDispatcher
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
        lords_address: ContractAddress,
        dao_fee: felt252,
    }

    #[constructor]
    fn constructor(ref self: ContractState, _lords_address: ContractAddress, _fee: felt252) {
        self.lords_address.write(_lords_address);
        self.dao_fee.write(_fee);
    }

    #[external(v0)]
    impl Market of IMarket<ContractState> {
        /// Creates a new market order.
        /// This function checks if the collection is whitelisted, approves the contract to transfer the NFT,
        /// increments the order count, sets the market order in state, and emits an OrderEvent.
        /// # Arguments
        /// * `market_order` - The market order to be created.
        fn create(ref self: ContractState, market_order: MarketOrder) {
            // check whitelist collection
            let collection_address = self
                .collection_address
                .read(market_order.collection_id.into());

            // assert collection is whitelisted
            assert(collection_address.into() != 0, 'MARKET: Not whitelisted');

            // approve contract to transfer NFT
            IERC721Dispatcher { contract_address: collection_address }
                .approve(get_contract_address(), market_order.token_id.into());

            // increment
            let mut count = self.order_count.read();
            count += 1;

            // set bounty // set count // set owner of bounty
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
            // get order
            let mut market_order = self.market_order.read(order_id);

            // get owner
            let order_owner = self.owner.read(order_id);

            // get collection
            let collection_address = self
                .collection_address
                .read(market_order.collection_id.into());

            // assert active
            market_order.is_active();

            // calculate cost minus fee
            let cost = market_order.price.into();
            let fee: u256 = cost * self.dao_fee.read().into() / 10000;

            // Lords token dispatcher
            let lords_dispatcher = IERC20CamelDispatcher {
                contract_address: self.lords_address.read(),
            };

            // transfer fee to DAO
            lords_dispatcher.transferFrom(get_caller_address(), get_contract_address(), fee.into());

            // transfer cost minus fee from buyer to seller
            lords_dispatcher
                .transferFrom(get_caller_address(), order_owner, (cost.into() - fee).into());

            // transfer NFT from seller to buyer
            IERC721Dispatcher { contract_address: collection_address }
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
            assert(
                self.owner.read(order_id) == get_caller_address(), 'MARKET: caller not order owner'
            );

            // revoke approval
            IERC721Dispatcher {
                contract_address: self.collection_address.read(market_order.collection_id.into())
            }
                .set_approval_for_all(get_contract_address(), false);

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
        fn edit(ref self: ContractState, order_id: felt252) {
            // get order
            let mut market_order = self.market_order.read(order_id);

            // assert active
            market_order.is_active();

            // assert owner
            assert(
                self.owner.read(order_id) == get_caller_address(), 'MARKET: caller not order owner'
            );

            // write
            self.market_order.write(order_id, market_order);

            // emit event
            self.emit(OrderEvent { market_order, timestamp: get_block_timestamp() });
        }
        fn whitelist_collection(ref self: ContractState, collection_address: ContractAddress) {
            // increment
            let mut count = self.collection_count.read();
            count += 1;

            // set count // set owner of bounty
            self.collection_address.write(count, collection_address);
            self.collection_count.write(count);
        }
        fn update_dao_fee(ref self: ContractState, fee: felt252) {
            self.dao_fee.write(fee);
        }
    }
}
