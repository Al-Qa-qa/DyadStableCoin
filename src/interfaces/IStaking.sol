// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IStaking {
  error NotOwnerOfNote();
  error InvalidAmount();
  error NotAuthorized();
  error RewardRateIsZero();
  error RewardAmountExceedsBalance();
  error RewardDurationNotFinished();

  event Staked                (uint256 indexed noteId, uint amount);
  event Withdrawn             (uint256 indexed noteId, uint amount);
  event RewardPaid            (uint256 indexed noteId, uint reward);
  event RewardAdded           (uint reward);
  event RewardsDurationUpdated(uint newDuration);
}
