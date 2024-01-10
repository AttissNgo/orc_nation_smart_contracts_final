## New contract addresses and ABI files
Everything can be found in the `json_out` directory. No need to compile contracts to get the ABIs.

## Breaking changes
While no function signatures have changed, many function bodies and state variables have changed. I don't think there will be any breaking changes, but I cannot guarantee. If you encounter any issues with your UIs, first check the smart contracts, then contact me.

## to-do's
Everyone 
- Test minting through the portal (once it's set up). Use MANY different addresses, and don't use the address that's connected to the Payment splitter. Try minting a few tokens. Try minting a lot of tokens. Try triggering raffles. Take note of how much MATIC you're using for gas and we'll all compare. 
- Make sure all the tokens you've minted have URIs. We're still using dummy artwork, but make sure each token has a unique URI extension (i.e. ".../435.json") - if anything goes wrong contact Attiss immediately. 

Shree 
- Connect portal to new contracts
- Mint should permit a maximum of 10 tokens per transaction
- Whitelisted users can only mint 3 tokens TOTAL during presale (after that they can mint as many as they want)

Trevor
- Connect team UI to new contracts
- Confirm with Johan that whitelisting functionality is working (this can be done even after presale ends)

Attiss
- change metadata files 
- add correct URI to deployment script (for mainnet)
- add new Chainlink VRF subscription ID to deployment script (for mainnet)
- create new RPC with Alchemy or Infura
- double-check and confirm payee addresses & share percentages

Johan
- create .env file for PKs & RPC
- setup up Chainlink VRF subscription and fund with LINK
- add deployed contract addresses (Orc Nation and Raffle) as consumers (directly after mainnet deployment)
- mint 500 'owner' tokens (directly after mainnet deployment)

Femi 
- Pin new metadata to IPFS

## Minting 500 'owner' tokens
The following script can be run by any admin:
```
forge script script/OwnerMint.s.sol:OwnerMint --sig "mint(string)" "mumbai" --rpc-url $MUMBAI_RPC_URL --broadcast
```