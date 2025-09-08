const abi = [
  {
    "type": "function",
    "name": "PACKAGE_VERSION",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "string",
        "internalType": "string"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "TRANSFER_ERC20",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "TRANSFER_ERC721",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "domains",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "uint32[]",
        "internalType": "uint32[]"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "enrollRemoteRouter",
    "inputs": [
      {
        "name": "_domain",
        "type": "uint32",
        "internalType": "uint32"
      },
      {
        "name": "_router",
        "type": "bytes32",
        "internalType": "bytes32"
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "enrollRemoteRouters",
    "inputs": [
      {
        "name": "_domains",
        "type": "uint32[]",
        "internalType": "uint32[]"
      },
      {
        "name": "_addresses",
        "type": "bytes32[]",
        "internalType": "bytes32[]"
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "getOperationNonce",
    "inputs": [
      {
        "name": "sender",
        "type": "bytes32",
        "internalType": "bytes32"
      }
    ],
    "outputs": [
      {
        "name": "",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "handle",
    "inputs": [
      {
        "name": "_origin",
        "type": "uint32",
        "internalType": "uint32"
      },
      {
        "name": "_sender",
        "type": "bytes32",
        "internalType": "bytes32"
      },
      {
        "name": "_message",
        "type": "bytes",
        "internalType": "bytes"
      }
    ],
    "outputs": [],
    "stateMutability": "payable"
  },
  {
    "type": "function",
    "name": "hook",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "address",
        "internalType": "contract IPostDispatchHook"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "interchainSecurityModule",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "address",
        "internalType": "contract IInterchainSecurityModule"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "localDomain",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "uint32",
        "internalType": "uint32"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "mailbox",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "address",
        "internalType": "contract IMailbox"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "nextOperationId",
    "inputs": [
      {
        "name": "sender",
        "type": "bytes32",
        "internalType": "bytes32"
      }
    ],
    "outputs": [
      {
        "name": "",
        "type": "bytes32",
        "internalType": "bytes32"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "quoteGasPayment",
    "inputs": [
      {
        "name": "_destinationDomain",
        "type": "uint32",
        "internalType": "uint32"
      },
      {
        "name": "_action",
        "type": "uint96",
        "internalType": "uint96"
      }
    ],
    "outputs": [
      {
        "name": "",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "view"
  },
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
        "name": "quotes",
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
        "name": "quotes",
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
    "name": "routers",
    "inputs": [
      {
        "name": "_domain",
        "type": "uint32",
        "internalType": "uint32"
      }
    ],
    "outputs": [
      {
        "name": "",
        "type": "bytes32",
        "internalType": "bytes32"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "setDestinationGas",
    "inputs": [
      {
        "name": "domain",
        "type": "uint32",
        "internalType": "uint32"
      },
      {
        "name": "action",
        "type": "uint96",
        "internalType": "uint96"
      },
      {
        "name": "gas",
        "type": "uint128",
        "internalType": "uint128"
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "setDestinationGas",
    "inputs": [
      {
        "name": "gasConfigs",
        "type": "tuple[]",
        "internalType": "struct GasRouter.GasRouterConfig[]",
        "components": [
          {
            "name": "domain",
            "type": "uint32",
            "internalType": "uint32"
          },
          {
            "name": "action",
            "type": "uint96",
            "internalType": "uint96"
          },
          {
            "name": "gas",
            "type": "uint128",
            "internalType": "uint128"
          }
        ]
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "setHook",
    "inputs": [
      {
        "name": "_hook",
        "type": "address",
        "internalType": "address"
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "setInterchainSecurityModule",
    "inputs": [
      {
        "name": "_module",
        "type": "address",
        "internalType": "address"
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
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
  },
  {
    "type": "function",
    "name": "unenrollRemoteRouter",
    "inputs": [
      {
        "name": "_domain",
        "type": "uint32",
        "internalType": "uint32"
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "unenrollRemoteRouters",
    "inputs": [
      {
        "name": "_domains",
        "type": "uint32[]",
        "internalType": "uint32[]"
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "event",
    "name": "GasSet",
    "inputs": [
      {
        "name": "domain",
        "type": "uint32",
        "indexed": false,
        "internalType": "uint32"
      },
      {
        "name": "action",
        "type": "uint96",
        "indexed": false,
        "internalType": "uint96"
      },
      {
        "name": "gas",
        "type": "uint128",
        "indexed": false,
        "internalType": "uint128"
      }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "HookSet",
    "inputs": [
      {
        "name": "_hook",
        "type": "address",
        "indexed": false,
        "internalType": "address"
      }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "Initialized",
    "inputs": [
      {
        "name": "version",
        "type": "uint64",
        "indexed": false,
        "internalType": "uint64"
      }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "IsmSet",
    "inputs": [
      {
        "name": "_ism",
        "type": "address",
        "indexed": false,
        "internalType": "address"
      }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "ReceivedNFT",
    "inputs": [
      {
        "name": "operationId",
        "type": "bytes32",
        "indexed": true,
        "internalType": "bytes32"
      },
      {
        "name": "recipient",
        "type": "bytes32",
        "indexed": true,
        "internalType": "bytes32"
      },
      {
        "name": "tokenIds",
        "type": "uint256[]",
        "indexed": false,
        "internalType": "uint256[]"
      }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "ReceivedNFTPartial",
    "inputs": [
      {
        "name": "operationId",
        "type": "bytes32",
        "indexed": true,
        "internalType": "bytes32"
      },
      {
        "name": "tokenId",
        "type": "uint256",
        "indexed": true,
        "internalType": "uint256"
      },
      {
        "name": "recipients",
        "type": "bytes32[]",
        "indexed": false,
        "internalType": "bytes32[]"
      },
      {
        "name": "amounts",
        "type": "uint256[]",
        "indexed": false,
        "internalType": "uint256[]"
      }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "TransferRemoteNFT",
    "inputs": [
      {
        "name": "operationId",
        "type": "bytes32",
        "indexed": true,
        "internalType": "bytes32"
      },
      {
        "name": "destination",
        "type": "uint32",
        "indexed": true,
        "internalType": "uint32"
      },
      {
        "name": "recipient",
        "type": "bytes32",
        "indexed": true,
        "internalType": "bytes32"
      },
      {
        "name": "messageId",
        "type": "bytes32",
        "indexed": false,
        "internalType": "bytes32"
      },
      {
        "name": "tokenIds",
        "type": "uint256[]",
        "indexed": false,
        "internalType": "uint256[]"
      },
      {
        "name": "gasLimit",
        "type": "uint256",
        "indexed": false,
        "internalType": "uint256"
      }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "TransferRemoteNFTPartial",
    "inputs": [
      {
        "name": "operationId",
        "type": "bytes32",
        "indexed": true,
        "internalType": "bytes32"
      },
      {
        "name": "destination",
        "type": "uint32",
        "indexed": true,
        "internalType": "uint32"
      },
      {
        "name": "messageId",
        "type": "bytes32",
        "indexed": false,
        "internalType": "bytes32"
      },
      {
        "name": "recipients",
        "type": "bytes32[]",
        "indexed": false,
        "internalType": "bytes32[]"
      },
      {
        "name": "amounts",
        "type": "uint256[]",
        "indexed": false,
        "internalType": "uint256[]"
      },
      {
        "name": "gasLimit",
        "type": "uint256",
        "indexed": false,
        "internalType": "uint256"
      }
    ],
    "anonymous": false
  },
  {
    "type": "error",
    "name": "GasRouter__GasLimitNotSet",
    "inputs": [
      {
        "name": "domain",
        "type": "uint32",
        "internalType": "uint32"
      },
      {
        "name": "action",
        "type": "uint96",
        "internalType": "uint96"
      }
    ]
  },
  {
    "type": "error",
    "name": "InvalidInitialization",
    "inputs": []
  },
  {
    "type": "error",
    "name": "InvalidMessageType",
    "inputs": []
  },
  {
    "type": "error",
    "name": "NotInitializing",
    "inputs": []
  },
  {
    "type": "error",
    "name": "ReentrancyGuardReentrantCall",
    "inputs": []
  },
  {
    "type": "error",
    "name": "TotalAmountMustBeOne",
    "inputs": []
  }
] as const;

export default abi;
