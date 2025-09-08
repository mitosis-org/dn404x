const abi = [
  {
    "type": "function",
    "name": "quoteTransferRemoteNFT",
    "inputs": [
      {
        "name": "destination",
        "type": "uint32",
        "internalType": "uint32"
      },
      {
        "name": "recipient",
        "type": "bytes32",
        "internalType": "bytes32"
      },
      {
        "name": "tokenIds",
        "type": "uint256[]",
        "internalType": "uint256[]"
      }
    ],
    "outputs": [
      {
        "name": "",
        "type": "tuple[]",
        "internalType": "struct Quote[]",
        "components": [
          {
            "name": "token",
            "type": "address",
            "internalType": "address"
          },
          {
            "name": "amount",
            "type": "uint256",
            "internalType": "uint256"
          }
        ]
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "quoteTransferRemoteNFTPartial",
    "inputs": [
      {
        "name": "destination",
        "type": "uint32",
        "internalType": "uint32"
      },
      {
        "name": "tokenId",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "recipients",
        "type": "bytes32[]",
        "internalType": "bytes32[]"
      },
      {
        "name": "amounts",
        "type": "uint256[]",
        "internalType": "uint256[]"
      }
    ],
    "outputs": [
      {
        "name": "",
        "type": "tuple[]",
        "internalType": "struct Quote[]",
        "components": [
          {
            "name": "token",
            "type": "address",
            "internalType": "address"
          },
          {
            "name": "amount",
            "type": "uint256",
            "internalType": "uint256"
          }
        ]
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "transferRemoteNFT",
    "inputs": [
      {
        "name": "destination",
        "type": "uint32",
        "internalType": "uint32"
      },
      {
        "name": "recipient",
        "type": "bytes32",
        "internalType": "bytes32"
      },
      {
        "name": "tokenIds",
        "type": "uint256[]",
        "internalType": "uint256[]"
      }
    ],
    "outputs": [],
    "stateMutability": "payable"
  },
  {
    "type": "function",
    "name": "transferRemoteNFTPartial",
    "inputs": [
      {
        "name": "destination",
        "type": "uint32",
        "internalType": "uint32"
      },
      {
        "name": "tokenId",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "recipients",
        "type": "bytes32[]",
        "internalType": "bytes32[]"
      },
      {
        "name": "amounts",
        "type": "uint256[]",
        "internalType": "uint256[]"
      }
    ],
    "outputs": [],
    "stateMutability": "payable"
  }
] as const;

export default abi;
