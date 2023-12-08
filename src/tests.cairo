#[cfg(test)]
mod test {
    use core::debug::PrintTrait;

    use core::{
        array::{SpanTrait, ArrayTrait}, integer::u256_try_as_non_zero, traits::{TryInto, Into}, clone::Clone,
        poseidon::poseidon_hash_span, option::OptionTrait, box::BoxTrait,
        starknet::{
            get_caller_address, ContractAddress, ContractAddressIntoFelt252, contract_address_const,
            get_block_timestamp, info::BlockInfo, get_contract_address
        },
    };

    use marketplace::IMarketDispatcherTrait;
    use marketplace::packing::MarketOrder;

    use marketplace::tokens::erc721::MyNFT;
    use marketplace::{IMarket, IMarketDispatcher, Market};
    use openzeppelin::tests::mocks::erc20_mocks::{DualCaseERC20};

    use openzeppelin::tests::utils::constants::{
        DATA, ZERO, OWNER, RECIPIENT, SPENDER, OPERATOR, OTHER, NAME, SYMBOL, URI, PUBKEY
    };
    use openzeppelin::tests::utils;
    use openzeppelin::token::erc20::interface::{
        IERC20Camel, IERC20CamelDispatcher, IERC20CamelDispatcherTrait, IERC20CamelLibraryDispatcher
    };

    use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};

    use openzeppelin::token::erc721::interface::{IERC721Dispatcher, IERC721DispatcherTrait, IERC721LibraryDispatcher};
    use openzeppelin::utils::serde::SerializedAppend;
    use starknet::syscalls::deploy_syscall;
    use starknet::testing::{set_caller_address, set_contract_address};

    const MAX_LORDS: u256 = 10000000000000000000000000000000000000000;
    const APPROVE: u256 = 10000000000000000000000000000000000000000;

    fn DAO() -> ContractAddress {
        contract_address_const::<1>()
    }

    const TOKEN_ID: u256 = 1;
    const ORDER_ID: felt252 = 1;
    const SUPPLY: u256 = 300000000000000000000000;
    const FEE: felt252 = 300; // 3%

    const PRICE: u128 = 300000000000000000000;
    const NEW_PRICE: u128 = 400000000000000000000;

    // @dev:
    // RECIPIENT() = NFT owner
    // OWNER() = LORDS owner and buyer
    // OPERATOR() = Owner of Market

    // ==================== HELPERS ====================

    fn setup_nft() -> IERC721Dispatcher {
        let mut calldata = array![];
        calldata.append_serde(RECIPIENT());
        set_contract_address(OWNER());
        let target = utils::deploy(MyNFT::TEST_CLASS_HASH, calldata);

        IERC721Dispatcher { contract_address: target }
    }

    fn setup_lords() -> IERC20Dispatcher {
        let mut calldata = array![];
        calldata.append_serde(NAME);
        calldata.append_serde(SYMBOL);
        calldata.append_serde(SUPPLY);
        calldata.append_serde(OWNER());
        let target = utils::deploy(DualCaseERC20::TEST_CLASS_HASH, calldata);
        IERC20Dispatcher { contract_address: target }
    }

    fn setup_market() -> (IMarketDispatcher, IERC20Dispatcher, IERC721Dispatcher) {
        let lords = setup_lords();

        let nft = setup_nft();

        set_contract_address(OPERATOR());

        let mut calldata = array![];
        calldata.append_serde(lords.contract_address);
        calldata.append_serde(FEE);
        calldata.append_serde(DAO());
        let target = utils::deploy(Market::TEST_CLASS_HASH, calldata);

        let market = IMarketDispatcher { contract_address: target };

        set_contract_address(DAO());
        market.whitelist_collection(nft.contract_address);
        (market, lords, nft)
    }

    fn create_with_approval() -> (IMarketDispatcher, IERC20Dispatcher, IERC721Dispatcher) {
        let (market, lords, nft) = setup_market();

        set_contract_address(RECIPIENT());

        // approve market to transfer
        nft.set_approval_for_all(market.contract_address, true);

        market
            .create(
                token_id: TOKEN_ID.try_into().unwrap(),
                collection_id: 1,
                price: PRICE,
                expiration: get_block_timestamp() + 86401,
            );

        (market, lords, nft)
    }

    // ==================== TESTS ====================

    // ==================== CREATE ====================

    #[test]
    #[available_gas(200000000)]
    fn test_create_with_approval() {
        let (market, lords, nft) = create_with_approval();
    }

    #[test]
    #[should_panic(expected: ('MARKET: Not approved', 'ENTRYPOINT_FAILED'))]
    #[available_gas(200000000)]
    fn test_create_with_without_approval() {
        let (market, lords, nft) = setup_market();

        set_contract_address(RECIPIENT());

        market.create(token_id: TOKEN_ID.try_into().unwrap(), collection_id: 1, price: PRICE, expiration: 100,);
    }
    // ==================== ACCEPT ====================

    #[test]
    #[available_gas(200000000)]
    fn test_accept() {
        let (market, lords, nft) = create_with_approval();

        set_contract_address(OWNER());

        // approve market to transfer
        lords.approve(market.contract_address, PRICE.into());

        // accept order
        market.accept(ORDER_ID);

        // assert OWNER() has the NFT
        assert(nft.owner_of(TOKEN_ID) == OWNER(), 'Wrong new owner');

        // Calculate fee
        let cost = PRICE.into();
        let fee: u256 = cost * FEE.into() / 10000;

        // assert RECIPIENT() has the LORDS - fee
        assert(lords.balance_of(RECIPIENT()) == (PRICE.into() - fee), 'Wrong seller balance');

        // assert DAO() has the fee
        assert(lords.balance_of(DAO()) == fee, 'Wrong dao balance');

        let order = market.view_order(ORDER_ID);

        assert(!order.active, 'Not active');
    }

    // ==================== EDIT ====================

    #[test]
    #[available_gas(200000000)]
    fn test_edit() {
        let (market, lords, nft) = create_with_approval();

        set_contract_address(RECIPIENT());

        market.edit(ORDER_ID, NEW_PRICE);

        let order = market.view_order(ORDER_ID);

        assert(order.price == NEW_PRICE, 'Wrong price');
    }

    // ==================== CANCEL ====================
    #[test]
    #[available_gas(200000000)]
    fn test_cancel() {
        let (market, lords, nft) = create_with_approval();

        set_contract_address(RECIPIENT());

        // revoke approval
        nft.approve(0.try_into().unwrap(), TOKEN_ID);

        market.cancel(ORDER_ID);

        let order = market.view_order(ORDER_ID);

        assert(!order.active, 'Not active');
    }

    #[test]
    #[available_gas(200000000)]
    fn test_change_fee() {
        let (market, lords, nft) = create_with_approval();

        set_contract_address(DAO());

        market.update_market_fee(400);
    }

    #[test]
    #[should_panic(expected: ('MARKET: caller not owner', 'ENTRYPOINT_FAILED'))]
    #[available_gas(200000000)]
    fn test_change_fee_panic() {
        let (market, lords, nft) = create_with_approval();

        set_contract_address(RECIPIENT());

        market.update_market_fee(400);
    }
}
