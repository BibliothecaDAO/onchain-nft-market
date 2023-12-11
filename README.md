# onchain NFT Market

Simple Starknet onchain Market

### Environment Configuration

```bash
# Set the StarkNet network to mainnet
export STARKNET_NETWORK="goerli"

# Starkli commands
starkli
starkli account oz init ./account
starkli account deploy ./account

# Set StarkNet RPC for mainnet and goerli
export STARKNET_RPC="https://starknet-mainnet.g.alchemy.com/v2/G9wJH34O_F038b_k329lcjOd_o38JA3j"
export STARKNET_RPC="https://starknet-goerli.g.alchemy.com/v2/-RHvatMphky_TLyhARL-4imNkCmPqQgS"

# Set the keystore path
export STARKNET_KEYSTORE=<PATH>

# Declare and deploy contracts
starkli declare /Users/os/Documents/code/biblio/onchain-nft-market/target/dev/marketplace_Market.contract_class.json --account ./account --keystore ./keys
starkli deploy 0x052a47b54f4358723850764585c9eafdcb8eec2e36874f9394a6643bd79bf982 $LORDS_ADDRESS 500 $DAO_ADDRESS --account ./account --keystore ./keys

# then

export MARKET_ADDRESS=0x07724c0cc6d78237b0c6103eb545c4f8560389145d87e02057c093bc9c275cd0
```

### Configuration for Goerli and Mainnet

```bash
# Goerli
export LORDS_ADDRESS=0x05e367ac160e5f90c5775089b582dfc987dd148a5a2f977c49def2a6644f724b
export BEASTS_ADDRESS=0x05c909139dbef784180eef8ce7a2f5bf52afe567aa73aaa77b8d8243ad5b6b96
export GOLDEN_TOKEN_ADDRESS=0x003583470A8943479F8609192Da4427caC45BdF66a58C84043c7Ab2FC722C0C0
export DAO_ADDRESS=0x45419c8e879021144134bf9cafe8071f3666d1ce8968551e739df2ee8b38db1

# Mainnet
export LORDS_ADDRESS=0x0124aeb495b947201f5fac96fd1138e326ad86195b98df6dec9009158a533b49
export BEASTS_ADDRESS=0x0158160018d590d93528995b340260e65aedd76d28a686e9daa5c4e8fad0c5dd
export GOLDEN_TOKEN_ADDRESS=0x04f5e296c805126637552cf3930e857f380e7c078e8f00696de4fc8545356b1d
export ARCADE_ACCOUNT_CLASS_HASH=0x0251830adc3d8b4d818c2c309d71f1958308e8c745212480c26e01120c69ee49
export DAO_ADDRESS=0x65ce28a1d99a085a0d5b4d07ceb9b80a9ef0e64a525bf526cff678c619fc4b1
```

### Whitelist Collections

```bash
# Add whitelist
starkli invoke $MARKET_ADDRESS whitelist_collection $GOLDEN_TOKEN_ADDRESS --account ./account --keystore ./keys

starkli invoke $MARKET_ADDRESS whitelist_collection $BEASTS_ADDRESS --account ./account --keystore ./keys
```

### test 

```bash
starkli declare /Users/os/Documents/code/biblio/onchain-nft-market/target/dev/marketplace_MyNFT.contract_class.json --account ./account --keystore ./keys
```