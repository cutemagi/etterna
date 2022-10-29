#include "Etterna/Globals/global.h"
#include "Etterna/Models/HighScore/HighScore.h"
#include "Etterna/Actor/Gameplay/Player.h"
#include "Etterna/Actor/Gameplay/LifeMeterBar.h"
#include "ReplayManager.h"

#include <memory>

std::shared_ptr<ReplayManager> REPLAYS = nullptr;
Replay* dummyReplay = new Replay;

static HighScore* activeReplayScore = nullptr;
static Replay* activeReplay = nullptr;
static TemporaryReplaySettings activeReplaySettings{};

Replay*
ReplayManager::GetReplay(HighScore* hs) {
	if (hs == nullptr) {
		return dummyReplay;
	}
	const auto key = hs->GetScoreKey();
	auto it = scoresToReplays.find(key);
	if (it == scoresToReplays.end()) {
		Replay* replay = new Replay(hs);
		std::pair<unsigned, Replay*> value(1, replay);
		scoresToReplays.emplace(key, value);
		return replay;
	} else {
		it->second.first++;
		return it->second.second;
	}
}

void
ReplayManager::ReleaseReplay(Replay* replay) {
	if (replay == nullptr) {
		return;
	}
	const auto key = replay->GetScoreKey();
	auto it = scoresToReplays.find(key);
	if (it == scoresToReplays.end()) {
		Locator::getLogger()->warn(
		  "Tried to free replay {} with no existing refs! Programming error!",
		  key);
	} else {
		it->second.first--;
		if (it->second.first <= 0) {
			Locator::getLogger()->trace("Freeing replay {}", key);
			delete it->second.second;
			scoresToReplays.erase(it);
		}
	}
}

ReplayManager::ReplayManager() {
	// Register with Lua.
	Lua* L = LUA->Get();
	lua_pushstring(L, "REPLAYS");
	this->PushSelf(L);
	lua_settable(L, LUA_GLOBALSINDEX);
	LUA->Release(L);
}

ReplayManager::~ReplayManager() {
	// under normal conditions LUA is null
	// but if this is triggered otherwise, this should happen
	if (LUA != nullptr) {
		// Unregister with Lua.
		LUA->UnsetGlobal("REPLAYS");
	}
}

// this is a static function
TapNoteScore
ReplayManager::GetTapNoteScoreForReplay(float fNoteOffset, float timingScale)
{
	// This code is basically a copy paste from somewhere in Player for grabbing
	// scores.

	const auto fSecondsFromExact = fabsf(fNoteOffset);

	if (fSecondsFromExact >= 1.f)
		return TNS_Miss;

	if (fSecondsFromExact <=
		Player::GetWindowSecondsCustomScale(TW_W1, timingScale))
		return TNS_W1;
	else if (fSecondsFromExact <=
			 Player::GetWindowSecondsCustomScale(TW_W2, timingScale))
		return TNS_W2;
	else if (fSecondsFromExact <=
			 Player::GetWindowSecondsCustomScale(TW_W3, timingScale))
		return TNS_W3;
	else if (fSecondsFromExact <=
			 Player::GetWindowSecondsCustomScale(TW_W4, timingScale))
		return TNS_W4;
	else if (fSecondsFromExact <=
			 std::max(Player::GetWindowSecondsCustomScale(TW_W5, timingScale),
					  MISS_WINDOW_BEGIN_SEC))
		return TNS_W5;
	return TNS_None;
}

Replay*
ReplayManager::InitReplayPlaybackForScore(HighScore* hs, float timingScale)
{
	UnsetActiveReplay();

	activeReplayScore = hs;
	activeReplay = GetReplay(hs);
	activeReplaySettings.reset();

	activeReplay->GenerateJudgeInfoAndReplaySnapshots(0, timingScale);

	return activeReplay;
}

void
ReplayManager::UnsetActiveReplay()
{
	if (activeReplay != nullptr && activeReplay != dummyReplay) {
		ReleaseReplay(activeReplay);
	}
	activeReplayScore = nullptr;
	activeReplay = GetReplay(nullptr);
	activeReplaySettings.reset();
}

Replay*
ReplayManager::GetActiveReplay()
{
	if (activeReplay == nullptr) {
		return dummyReplay;
	}
	return activeReplay;
}

HighScore*
ReplayManager::GetActiveReplayScore()
{
	return activeReplayScore;
}

void
ReplayManager::StoreActiveReplaySettings(float replayRate,
										 std::string& replayModifiers,
										 bool replayUsedMirror,
										 float oldRate,
										 std::string& oldModifiers,
										 FailType oldFailType,
										 std::string& oldNoteskin)
{
	activeReplaySettings.replayRate = replayRate;
	activeReplaySettings.replayModifiers = replayModifiers;
	activeReplaySettings.replayUsedMirror = replayUsedMirror;
	activeReplaySettings.oldRate = oldRate;
	activeReplaySettings.oldModifiers = oldModifiers;
	activeReplaySettings.oldFailType = oldFailType;
	activeReplaySettings.oldNoteskin = oldNoteskin;
}

TemporaryReplaySettings
ReplayManager::GetActiveReplaySettings()
{
	return activeReplaySettings;
}

auto
ReplayManager::CalculateRadarValuesForReplay(Replay& replay, RadarValues& rv, RadarValues& possibleRV)
  -> bool
{
	Locator::getLogger()->info("Calculating Radar Values from ReplayData");

	// We will do this thoroughly just in case someone decides to use the
	// other categories we don't currently use
	auto tapsHit = 0;
	auto jumpsHit = 0;
	auto handsHit = 0;
	auto holdsHeld = possibleRV[RadarCategory_Holds];
	auto rollsHeld = possibleRV[RadarCategory_Rolls];
	auto liftsHit = 0;
	auto fakes = possibleRV[RadarCategory_Fakes];
	auto totalNotesHit = 0;
	auto minesMissed = possibleRV[RadarCategory_Mines];

	auto& ji = replay.GetJudgeInfo();
	auto& m_ReplayTapMap = ji.trrMap;
	auto& m_ReplayHoldMap = ji.hrrMap;

	// For every row recorded...
	for (auto& row : m_ReplayTapMap) {
		auto tapsOnThisRow = 0;
		// For every tap on these rows...
		for (auto& trr : row.second) {
			if (trr.type == TapNoteType_Fake) {
				fakes--;
				continue;
			}
			if (trr.type == TapNoteType_Mine) {
				minesMissed--;
				continue;
			}
			if (trr.type == TapNoteType_Lift) {
				liftsHit++;
				continue;
			}
			tapsOnThisRow++;
			// We handle Empties as well because that's what old replays are
			// loaded as.
			if (trr.type == TapNoteType_Tap ||
				trr.type == TapNoteType_HoldHead ||
				trr.type == TapNoteType_Empty) {
				totalNotesHit++;
				tapsHit++;
				if (tapsOnThisRow == 2) {
					// This is technically incorrect.
					jumpsHit++;
				} else if (tapsOnThisRow >= 3) {
					handsHit++;
				}
				continue;
			}
		}
	}

	// For every hold recorded...
	for (auto& row : m_ReplayHoldMap) {
		// For every hold on this row...
		for (auto& hrr : row.second) {
			if (hrr.subType == TapNoteSubType_Hold) {
				holdsHeld--;
				continue;
			} else if (hrr.subType == TapNoteSubType_Roll) {
				rollsHeld--;
				continue;
			}
		}
	}

	// lol just set them
	rv[RadarCategory_TapsAndHolds] = tapsHit;
	rv[RadarCategory_Jumps] = jumpsHit;
	rv[RadarCategory_Holds] = holdsHeld;
	rv[RadarCategory_Mines] = minesMissed;
	rv[RadarCategory_Hands] = handsHit;
	rv[RadarCategory_Rolls] = rollsHeld;
	rv[RadarCategory_Lifts] = liftsHit;
	rv[RadarCategory_Fakes] = fakes;
	rv[RadarCategory_Notes] = totalNotesHit;

	Locator::getLogger()->info(
	  "Finished Calculating Radar Values from ReplayData");
	return true;
}

auto
ReplayManager::SetPlayerStageStatsForReplay(Replay& replay, PlayerStageStats* pss, float ts)
  -> bool
{
	Locator::getLogger()->info("Entered PSSFromReplayData function");

	// Radar values.
	// The possible radar values have already been handled, so we just do
	// the real values.
	RadarValues rrv;
	CalculateRadarValuesForReplay(replay, rrv, pss->m_radarPossible);
	pss->m_radarActual.Zero();
	pss->m_radarActual += rrv;
	pss->everusedautoplay = true;

	auto* pScoreData = replay.GetHighScore();
	if (pScoreData == nullptr) {
		Locator::getLogger()->warn(
		  "Failed to set PlayerStageStats for replay on score {} because "
		  "highscore could not be found",
		  replay.GetScoreKey());
		return false;
	}

	// Judgments
	for (int i = TNS_Miss; i < NUM_TapNoteScore; i++) {
		pss->m_iTapNoteScores[i] = pScoreData->GetTapNoteScore((TapNoteScore)i);
	}
	for (auto i = 0; i < NUM_HoldNoteScore; i++) {
		pss->m_iHoldNoteScores[i] =
		  pScoreData->GetHoldNoteScore((HoldNoteScore)i);
	}

	// ReplayData
	pss->m_HighScore = *pScoreData;
	pss->CurWifeScore = pScoreData->GetWifeScore();
	pss->m_fWifeScore = pScoreData->GetWifeScore();
	pss->m_vHoldReplayData = pScoreData->GetHoldReplayDataVector();
	pss->m_vNoteRowVector = pScoreData->GetNoteRowVector();
	pss->m_vOffsetVector = pScoreData->GetOffsetVector();
	pss->m_vTapNoteTypeVector = pScoreData->GetTapNoteTypeVector();
	pss->m_vTrackVector = pScoreData->GetTrackVector();
	pss->InputData = pScoreData->GetInputDataVector();

	// Life record
	pss->m_fLifeRecord.clear();
	pss->m_fLifeRecord = GenerateLifeRecordForReplay(replay, ts);
	pss->m_ComboList.clear();
	pss->m_ComboList = GenerateComboListForReplay(replay, ts);

	Locator::getLogger()->info("Finished PSSFromReplayData function");
	return true;
}

std::map<float, float>
ReplayManager::GenerateLifeRecordForReplay(Replay& replay, float timingScale)
{
	Locator::getLogger()->info("Generating LifeRecord from ReplayData");

	// Without a Snapshot Map, I assume we didn't calculate
	// the other necessary stuff and this is going to turn out bad
	if (replay.GetReplaySnapshotMap().empty()) {
		Locator::getLogger()->warn(
		  "Failed to generate LifeRecord for replay of score {} because the "
		  "snapshot map was empty",
		  replay.GetScoreKey());
		return std::map<float, float>({ { 0.f, 0.5f } });
	}

	std::map<float, float> lifeRecord;
	auto lifeLevel = 0.5f;
	lifeRecord[0.f] = lifeLevel;
	const auto rateUsed = replay.GetMusicRate();
	auto allOffset = 0.f;

	auto* td = replay.GetTimingData();
	if (td == nullptr) {
		Locator::getLogger()->warn("Failed to generate LifeRecord for replay of "
								   "score {} because timing data did not exist",
								   replay.GetScoreKey());
		return std::map<float, float>({ { 0.f, 0.5f } });
	}


	const auto firstSnapshotTime =
	  td->WhereUAtBro(replay.GetReplaySnapshotMap().begin()->first);
	auto& ji = replay.GetJudgeInfo();
	auto& m_ReplayHoldMapByElapsedTime = ji.hrrMapByElapsedTime;
	auto& m_ReplayTapMapByElapsedTime = ji.trrMapByElapsedTime;
	auto holdIter = m_ReplayHoldMapByElapsedTime.begin();
	auto tapIter = m_ReplayTapMapByElapsedTime.begin();

	// offset everything by the first snapshot barely
	if (!m_ReplayTapMapByElapsedTime.empty())
		allOffset = firstSnapshotTime + 0.001f;

	// but if a hold messed with life before that somehow
	// offset by that instead
	// check for the offset less than the holditer because at this point
	// it is either 0 or a number greater than it should be
	// realistically this doesnt actually matter at all if we only track dropped
	// holds but im putting it here anyways
	if (!m_ReplayHoldMapByElapsedTime.empty() && holdIter->first > 0 &&
		allOffset > holdIter->first + 0.001f)
		allOffset = holdIter->first + 0.001f;

	// Continue until both iterators have finished
	while (holdIter != m_ReplayHoldMapByElapsedTime.end() ||
		   tapIter != m_ReplayTapMapByElapsedTime.end()) {
		auto now = 0.f;
		auto lifeDelta = 0.f;
		// Use tapIter for this iteration if:
		//	holdIter is finished
		//	tapIter comes first
		if (holdIter == m_ReplayHoldMapByElapsedTime.end() ||
			(tapIter != m_ReplayTapMapByElapsedTime.end() &&
			 holdIter != m_ReplayHoldMapByElapsedTime.end() &&
			 tapIter->first < holdIter->first)) {
			now = tapIter->first;
			for (auto& trr : tapIter->second) {
				TapNoteScore tns;
				if (trr.type != TapNoteType_Mine)
					tns = GetTapNoteScoreForReplay(trr.offset, timingScale);
				else
					tns = TNS_HitMine;
				lifeDelta += LifeMeterBar::MapTNSToDeltaLife(tns);
			}
			++tapIter;
		}
		// Use holdIter for this iteration if:
		//	tapIter is finished
		//	holdIter comes first
		else if (tapIter == m_ReplayTapMapByElapsedTime.end() ||
				 (holdIter != m_ReplayHoldMapByElapsedTime.end() &&
				  tapIter != m_ReplayTapMapByElapsedTime.end() &&
				  holdIter->first < tapIter->first)) {
			now = holdIter->first;
			for (auto& hrr : holdIter->second) {
				lifeDelta += LifeMeterBar::MapHNSToDeltaLife(HNS_LetGo);
			}
			++holdIter;
		} else {
			Locator::getLogger()->warn(
			  "Somehow while calculating the life graph, something "
			  "went wrong.");
			++holdIter;
			++tapIter;
		}

		lifeLevel += lifeDelta;
		CLAMP(lifeLevel, 0.f, 1.f);
		lifeRecord[(now - allOffset) / rateUsed] = lifeLevel;
	}

	Locator::getLogger()->info(
	  "Finished Generating LifeRecord from ReplayData");
	return lifeRecord;
}

std::vector<PlayerStageStats::Combo_t>
ReplayManager::GenerateComboListForReplay(Replay& replay, float timingScale)
{
	Locator::getLogger()->info("Generating ComboList from ReplayData");

	std::vector<PlayerStageStats::Combo_t> combos;
	const PlayerStageStats::Combo_t firstCombo;
	combos.push_back(firstCombo);

	auto* td = replay.GetTimingData();
	if (td == nullptr) {
		Locator::getLogger()->warn("Failed to generate ComboList for replay of "
								   "score {} because timing data did not exist",
								   replay.GetScoreKey());
		return combos;
	}

	auto& m_ReplaySnapshotMap = replay.GetReplaySnapshotMap();
	const auto rateUsed = replay.GetMusicRate();
	auto allOffset = 0.f;

	// Without a Snapshot Map, I assume we didn't calculate
	// the other necessary stuff and this is going to turn out bad
	if (m_ReplaySnapshotMap.empty()) {
		Locator::getLogger()->warn("Failed to generate ComboList for replay of "
								   "score {} because snapshot map was empty",
								   replay.GetScoreKey());
		return combos;
	}

	auto& ji = replay.GetJudgeInfo();
	auto& m_ReplayHoldMapByElapsedTime = ji.hrrMapByElapsedTime;
	auto& m_ReplayTapMapByElapsedTime = ji.trrMapByElapsedTime;
	const auto firstSnapshotTime =
	  td->WhereUAtBro(m_ReplaySnapshotMap.begin()->first);
	auto curCombo = &(combos[0]);
	auto rowOfComboStart = m_ReplayTapMapByElapsedTime.begin();

	// offset all entries by the offset of the first note
	// unless it's negative, then just ... dont
	if (!m_ReplayTapMapByElapsedTime.empty() && rowOfComboStart->first > 0)
		allOffset = firstSnapshotTime + 0.001f;

	// Go over all chronological tap rows (only taps should accumulate
	// combo)
	for (auto tapIter = m_ReplayTapMapByElapsedTime.begin();
		 tapIter != m_ReplayTapMapByElapsedTime.end();
		 ++tapIter) {
		auto& trrv = tapIter->second;
		// Sort the vector of taps for this row
		// by their offset values so we manage them in order
		std::sort(trrv.begin(),
				  trrv.end(),
				  [](const TapReplayResult& lhs, const TapReplayResult& rhs) {
					  return lhs.offset < rhs.offset;
				  });

		// Handle the taps for this row in order
		for (const auto& trr : trrv) {
			// Mines do not modify combo
			if (trr.type == TapNoteType_Mine)
				continue;

			// If CB, make a new combo
			// If not CB, increment combo
			const auto tns = GetTapNoteScoreForReplay(trr.offset, timingScale);
			if (tns == TNS_Miss || tns == TNS_W5 || tns == TNS_W4) {
				const auto start =
				  (rowOfComboStart->first - allOffset) / rateUsed;
				const auto finish = (tapIter->first - allOffset) / rateUsed;
				curCombo->m_fSizeSeconds = finish - start;
				curCombo->m_fStartSecond = start;

				PlayerStageStats::Combo_t nextcombo;
				combos.emplace_back(nextcombo);
				curCombo = &(combos.back());
				rowOfComboStart = tapIter;
			} else if (tns == TNS_W1 || tns == TNS_W2 || tns == TNS_W3) {
				curCombo->m_cnt++;
			}
		}
	}
	// The final combo may not have properly ended, end it here
	curCombo->m_fSizeSeconds =
	  (m_ReplayTapMapByElapsedTime.rbegin()->first - allOffset) / rateUsed -
	  (rowOfComboStart->first - allOffset) / rateUsed;
	curCombo->m_fStartSecond = (rowOfComboStart->first - allOffset) / rateUsed;

	Locator::getLogger()->info("Finished Generating ComboList from ReplayData");
	return combos;
}

#include "Etterna/Models/Lua/LuaBinding.h"
class LunaReplayManager : public Luna<ReplayManager>
{
  public:

	static int GetReplay(T* p, lua_State* L)
	{
		HighScore* hs = Luna<HighScore>::check(L, 1);
		// TODO: THIS LEAKS REPLAY REFS!!!!!!!!!!!!
		p->GetReplay(hs)->PushSelf(L);
		return 1;
	}

	LunaReplayManager()
	{
		ADD_METHOD(GetReplay);
	}
};
LUA_REGISTER_CLASS(ReplayManager)
