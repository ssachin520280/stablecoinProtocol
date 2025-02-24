-include .env

.PHONY: all test deploy

build :; forge build

test :; forge test

testOnSepolia :
	@forge test --rpc-url $(SEPOLIA_RPC_URL)
