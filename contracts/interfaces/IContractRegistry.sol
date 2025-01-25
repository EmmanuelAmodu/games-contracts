// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

interface IContractRegistry {
    function setAllowedContract(bytes32 _clientId, address _contract, bool _allowed) external;
    function isContractAllowed(bytes32 _clientId, address _contract) external view returns (bool);
}
