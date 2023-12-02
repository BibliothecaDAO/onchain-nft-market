#[starknet::contract]
mod MyNFT {
    use openzeppelin::introspection::src5::SRC5Component;
    use openzeppelin::token::erc721::ERC721Component;
    use starknet::ContractAddress;

    component!(path: ERC721Component, storage: erc721, event: ERC721Event);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);

    // ERC721
    #[abi(embed_v0)]
    impl ERC721Impl = ERC721Component::ERC721Impl<ContractState>;
    #[abi(embed_v0)]
    impl ERC721MetadataImpl = ERC721Component::ERC721MetadataImpl<ContractState>;
    #[abi(embed_v0)]
    impl ERC721CamelOnly = ERC721Component::ERC721CamelOnlyImpl<ContractState>;
    #[abi(embed_v0)]
    impl ERC721MetadataCamelOnly =
        ERC721Component::ERC721MetadataCamelOnlyImpl<ContractState>;
    impl ERC721InternalImpl = ERC721Component::InternalImpl<ContractState>;

    // SRC5
    #[abi(embed_v0)]
    impl SRC5Impl = SRC5Component::SRC5Impl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        erc721: ERC721Component::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        ERC721Event: ERC721Component::Event,
        #[flat]
        SRC5Event: SRC5Component::Event
    }

    #[constructor]
    fn constructor(ref self: ContractState, recipient: ContractAddress) {
        let name = 'MyNFT';
        let symbol = 'NFT';
        let token_id = 1;
        let token_uri = 'NFT_URI';

        self.erc721.initializer(name, symbol);
        self._mint_with_uri(recipient, token_id, token_uri);
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn _mint_with_uri(
            ref self: ContractState, recipient: ContractAddress, token_id: u256, token_uri: felt252
        ) {
            // Initialize the ERC721 storage
            self.erc721._mint(recipient, token_id);
            // Mint the NFT to recipient and set the token's URI
            self.erc721._set_token_uri(token_id, token_uri);
        }
    }
}
