if not bizstring then
	error("BizHawk emu ( + Faust Snes core ) only.")
end

package.path = package.path..";lua\\?.lua"
require "lib_EmuWrapper"
require "lib_text"
require "lib_text_j"
require "itemName"
require "lib_input2"
require "item_log" -- by Append 20250819
item_log.initialize_textlog() -- by Append 20250819

cpu_ = cpu
cpu = ew.cpu
cpu2 = ew.cpu2
cpu3 = ew.cpu3
cpu4 = ew.cpu4

-------------------- アドレスとそのアドレスからのサイズ --------------------

local addrParamForSynchronizing = 0x7F7000 --同期時に書き込むパラメータのアドレス
local sizeParamForSynchronizing = 0x80 --同期時に書き込むパラメータのサイズ
local addrParamOnROM = {0xBFC400,0xBFC400,0xCFC400} --ROM上のパラメータのアドレス
local addrMultiworldInfo = {0xBFFDD0,0xBFFDD0,0xCFFDD0} --ROM上のマルチワールド情報のアドレス
local addrBinaryId = {0xBFFDD8,0xBFFDD8,0xCFFDD8} --ROM上のバイナリ識別情報のアドレス
local addrSValue = 0x7FFFA0 --同期用の値
local addrSInfo = 0x7FFFEC --同期時の情報

local addrItems = 0x7FFF00 --[60]全タイトル分
local addrChecks = 0x7FFF60 --[20]そのタイトル分
local addrChecksSeen = 0x7FFF80 --[20]そのタイトル分
local addrPlayFrames0 = 0x7E0240 --[2]
local addrPlayFrames1 = 0x7FFFF0 --[2]
local addrClearFrames = 0x7FFFF6 --[4]
local addrTiwns = {0x7E1F80,0x7E1FB3,0x7E1FB4} --[1]
local addrIFG = 0x7FFFAE --[1]
local addrLastProgressFrame = 0x7E0244
local addrHintOffset = 0x7E0246
local addrCheckSequence = {0xBF8200,0xBF8200,0xCF8200}

local addrTitleValueGreater = {
{0x7FFFD0,0x7FFFD1,0x7FFFD2,0x7FFFD3,0x7FFFD4,0x7FFFD5,0x7FFFD6,0x7FFFD7,0x7FFFD8,0x7FFFD9,0x7FFFDA,0x7FFFDB,0x7FFFDC,0x7FFFDD,0x7FFFDE,0x7FFFDF,0x7FFFCF},
{0x7FFFD0,0x7FFFD1,0x7FFFD2,0x7FFFD3,0x7FFFD4,0x7FFFD5,0x7FFFD6,0x7FFFD7,0x7FFFD8,0x7FFFD9,0x7FFFDA,0x7FFFDB,0x7FFFDC,0x7FFFDD,0x7FFFDE,0x7FFFDF,0x7FFFCF},
{0x7FFFD0,0x7FFFD1,0x7FFFD2,0x7FFFD3,0x7FFFD4,0x7FFFD5,0x7FFFD6,0x7FFFD7,0x7FFFD8,0x7FFFD9,0x7FFFDA,0x7FFFDB,0x7FFFDC,0x7FFFDD,0x7FFFDE,0x7FFFDF,0x7FFFCF},
}
local addrTitleValueOr = {
{},
{0x7E1FD9},
{0x7E1FDA},
}
local addrClear = {0x7FFFCF,0x7FFFCF,0x7FFFCF,}
local addrGameFrameCounter = {0x7E0B9C,0x7E09CC,0x7E09CC,}
local addrDefaultItems = {0xBFFDE0,0xBFFDE0,0xCFFDE0,}

-------------------- 定数 --------------------
local filename_boot = ".\\boot.smc"
local filename_game = {".\\bin\\x1.smc",".\\bin\\x2.smc",".\\bin\\x3.smc"}
local filenameSave = ".\\save.txt"
local filenameSavestateCoreInfo = ".\\savestateInfo.txt"

local cMS_switchGame = 0x00
local cMS_switchGameL = 0x01
local cMS_switchGameR = 0x02
local cMS_switchGameLR = 0x03
local cMS_saveState = 0x04
local cMS_queryClearStatus = 0x05

local cMI_atBossSelect = 0x01

local cItems = 0x60
local cChecksPerTitle = 0x20

-------------------- 変数 --------------------

local sessionInfo = {}
sessionInfo.games = 0
sessionInfo.randomizedGame = {false,false,false}
sessionInfo.param = ""
sessionInfo.currentGame = nil
sessionInfo.frameCounter = -1
sessionInfo.core = "unknown"
sessionInfo.defaultItem = {}

--セーブステート情報ファイルをロード/無かったらテーブル作成
lu.doFileSafe(filenameSavestateCoreInfo)
if not savestateCoreInfo then
savestateCoreInfo = {}
end

--セーブファイルをロード/無かったらテーブル作成
lu.doFileSafe(filenameSave)
if not sessionSave then
	sessionSave = {}
	sessionSave.items = {}
	sessionSave.checks = {}
	sessionSave.checksSeen = {}
	sessionSave.titleValue = {{},{},{}}
	sessionSave.playFrames = 0
	sessionSave.clearFrames = 0
	sessionSave.tiwns = 0
	sessionSave.ifg = 0
	sessionSave.lastProgressFrame = 0xFFFF
	sessionSave.hintOffset = 0
	sessionSave.autoSave = 1
	for i=0,cItems-1,1 do
		sessionSave.items[i] = 0x00
	end
	for i=0,cChecksPerTitle*3-1,1 do
		sessionSave.checks[i] = 0x00
		sessionSave.checksSeen[i] = 0x00
	end
end

-------------------- 関数 --------------------
--ちょっとした情報表示
local function quickInfo(str,timer)
	sessionInfo.info = str
	sessionInfo.infoTimer = timer
end

local function receiveSynchronizingValue(title)
	local SValue = cpu[addrSValue]
	if SValue >= 0x80 then
		local doSynchronize = true
		for i=0,sizeParamForSynchronizing-1,1 do
			if cpu[addrParamForSynchronizing+i] ~= cpu[addrParamOnROM[title]+i] then
				doSynchronize = false
				break
			end
		end
		if doSynchronize then
			return SValue
		end
	end
	return 0
end

local function getSaveStateFilename(title)
	return ".\\savestate_x" .. title .. ".State"
end


--パラメータ文字列返す。不適切なデータであればnilを返す。
--パラメータとして、01~1F・7F~FFを含んではならない。
--00を含む事は可能だが、一度出現したらそれ以降は全て00でなければならない。
local function getParamOnROM(title)
	local str = ""
	local zero = false
	for i=0,sizeParamForSynchronizing-1,1 do
		local value = cpu[addrParamOnROM[title]+i]
		if value == 0 then zero = true end
		if zero then
			if value ~= 0 then return nil end
		else
			if value >= 0x01 and value <= 0x1F then return nil end
			if value >= 0x7F then return nil end
			str = str .. string.char(value)
		end
	end
	return str
end

--同期するメモリを更新する。
--アイテムやチェックの獲得状態の更新はORで行われるためビットが減る事はない。
--他の値は、条件に応じてどちらからに設定される。
local function updateSaveValue(forceUpdate,atBoot)
	local updated = false
	local function synchronize_or(addr,name,offset)
		local value = cpu[addr] | sessionSave[name][offset]
		cpu[addr] = value
		if sessionSave[name][offset] ~= value then
			sessionSave[name][offset] = value
			updated = true
		end
	end
	local function updateSessionSave(name,value)
		if sessionSave[name] ~= value then
			sessionSave[name] = value
			updated = true
		end
	end

	for i=0,cItems-1,1 do
		synchronize_or(addrItems+i,"items",i)
	end
	for i=0,cChecksPerTitle-1,1 do
		local offset = (sessionInfo.currentGame-1)*cChecksPerTitle+i
		synchronize_or(addrChecks+i,"checks",offset)
		synchronize_or(addrChecksSeen+i,"checksSeen",offset)
	end
	
	if true then --プレイタイムを大きい方に更新する/この処理はアップデートフラグを立てない
		local value = math.max(
			(cpu2[addrPlayFrames1] << 16 ) | cpu2[addrPlayFrames0] ,
			sessionSave.playFrames
			)
		cpu2[addrPlayFrames0] = ( value & 0xFFFF )
		cpu2[addrPlayFrames1] = (( value >> 16 ) & 0xFFFF)
--		updateSessionSave("playFrames",value)
		sessionSave.playFrames = value --プレイタイムはupdatedを更新しない
	end
	if true then --クリアタイムを大きい方に更新する
		local value = math.max( cpu4[addrClearFrames] , sessionSave.clearFrames )
		cpu4[addrClearFrames] = value
		updateSessionSave("clearFrames",value)
	end
	if true then --やられた回数を大きい方に更新する
		local value = math.max(
			cpu[addrTiwns[sessionInfo.currentGame]] ,
			sessionSave.tiwns
			)
		cpu[addrTiwns[sessionInfo.currentGame]] = value
		updateSessionSave("tiwns",value)
	end
	if true then --無敵時間発生装置の回数を大きい方に更新する
		local value = math.max(
			cpu[addrIFG] ,
			sessionSave.ifg
			)
		cpu[addrIFG] = value
		updateSessionSave("ifg",value)
	end
	if true then --ゲーム固有の値を大きい方に更新する
		local tblAddr = addrTitleValueGreater[sessionInfo.currentGame]
		local tblDest = sessionSave.titleValue[sessionInfo.currentGame]
		for k,v in ipairs(tblAddr) do
			if not tblDest[v] then tblDest[v] = 0 end
			local value = math.max(cpu[v] , tblDest[v] )
			cpu[v] = value
			if tblDest[v] ~= value then
				tblDest[v] = value
				updated = true
			end
		end
	end
	if true then --ゲーム固有の値をORで更新する
		local tblAddr = addrTitleValueOr[sessionInfo.currentGame]
		local tblDest = sessionSave.titleValue[sessionInfo.currentGame]
		for k,v in ipairs(tblAddr) do
			if not tblDest[v] then tblDest[v] = 0 end
			local value = cpu[v] | tblDest[v]
			cpu[v] = value
			if tblDest[v] ~= value then
				tblDest[v] = value
				updated = true
			end
		end
	end
	if true then --ヒント/最終進捗フレーム/基本的にゲームのほうを優先するが、atBootがtrueならLuaを優先する
		local value = cpu2[addrLastProgressFrame]
		if atBoot then value = sessionSave.lastProgressFrame end
		cpu2[addrLastProgressFrame] = value
		updateSessionSave("lastProgressFrame",value)
	end
	if true then --ヒント/ヒントオフセット
		local value = math.max(
			cpu2[addrHintOffset] ,
			sessionSave.hintOffset
			)
		cpu2[addrHintOffset] = value
		updateSessionSave("hintOffset",value)
	end
	--
	if forceUpdate or updated then
		lu.saveTable(filenameSave,"sessionSave")
		if not sessionInfo.info then
			quickInfo("Saved.",30)
		end
	end
end

--sessionInfo.currentGameのゲームをロードする
local function loadGame()
	client.openrom(filename_game[sessionInfo.currentGame])
	ew.frameadvance()
	savestate.load(getSaveStateFilename(sessionInfo.currentGame))
	cpu[addrSValue] = 0
	updateSaveValue(false,true)
end

--ゲームを切り替える
local function switchGame(title)
	updateSaveValue(true)
	--直接指定が有効ならそのタイトルに、そうでないならタイトルを一つ進める
	if sessionInfo.currentGame ~= title and sessionInfo.randomizedGame[title] then
		sessionInfo.currentGame = title
	else
		while true do
			sessionInfo.currentGame = sessionInfo.currentGame + 1
			if sessionInfo.currentGame >= 4 then sessionInfo.currentGame = 1 end
			if sessionInfo.randomizedGame[sessionInfo.currentGame] then break end
		end
	end
	loadGame()
end

local function getHMMSS(frames)
	frames = _df( frames , 60 )
	local timeS = frames % 60
	frames = _df( frames , 60 )
	local timeM = frames % 60
	frames = _df( frames , 60 )
	local timeH = frames % 60
	return string.format("%d:%02d:%02d",timeH,timeM,timeS)
end

--ボスセレクトの表示で使うタイムとアイテム・チェックの表示
local function displayTimeAndItemsAndChecks()
	local time = (cpu2[addrPlayFrames1] << 16 ) | cpu2[addrPlayFrames0]

	local function countBit(value)
		local cnt = 0
		while value > 0 do
			if value % 2 == 1 then cnt = cnt + 1 end
			value = _df( value , 2 )
		end
		return cnt
	end

	local items = 0
	for i=0,cItems-1,1 do
		items = items + countBit(sessionSave.items[i])
	end
	items = items - 9 * 3 --強制的に1になるビットの分引く
	local checks = 0
	for i=0,cChecksPerTitle*3-1,1 do
		checks = checks + countBit(sessionSave.checks[i])
	end

	local str = string.format("%s Item:%3d Check:%3d",getHMMSS(time),items,checks)

	Text.out(0x80,0x8,str,ew.RGB(255,255,255),ew.RGBA(0,0,0,192))
end

--ボスセレクトでの表示
local function infoAtBossSelect()
	if sessionInfo.frameCounter % 60 < 30 then
		Text.out(0x20,0x8,"SELECT : Switch Game",ew.RGB(255,255,255),ew.RGBA(0,0,0,192))
	end
	displayTimeAndItemsAndChecks()
end

--ヒント情報を更新する/できればLua側でやりたくなかったが……
local function synchronizeHintInfo()
	local curGame = sessionInfo.currentGame
	local hintOffset = cpu2[addrHintOffset]

	if hintOffset >= 0x300 then return end
	for i=0,100,1 do
		local checkTitle = cpu[addrCheckSequence[curGame]+hintOffset+0x300]
		local checkId = cpu[addrCheckSequence[curGame]+hintOffset]
		if checkTitle == 0 or checkTitle >= 4 then break end
		local offset = ( checkTitle - 1 ) * cChecksPerTitle + _df( checkId , 8 )
		local mask = 1 << ( checkId % 8 )
		if curGame == checkTitle then --現在のゲームの場合はRAMを参照する
			local offsetAlt = offset % cChecksPerTitle
			if ( cpu[addrChecks + offsetAlt] & mask ) == 0 then break end
		else --現在のゲームでない場合はLuaのメモリを参照する
			if ( sessionSave.checks[offset] & mask ) == 0 then break end
		end
		hintOffset = hintOffset + 1
--		print( "Inc hintOffset " .. _hex(hintOffset-1) .. " > " .. _hex(hintOffset) .. ": ID:" .. _hex(checkTitle) .. _hex(checkId)) --debug
	end
	cpu2[addrHintOffset] = hintOffset
end

--獲得したアイテムの情報を表示する/できればゲーム側で処理すべきだが意地を張るより利点のほうが大きいと判断
local function acquiredItemInfo()
	--開始後1秒以内は処理しない
	if sessionInfo.frameCounter < 60 then return end

	--前fの獲得情報がなければ取得/その他初期化
	if not sessionInfo.previousAcquiredItem then
		sessionInfo.previousAcquiredItem = {}
		for i=0,cItems-1,1 do sessionInfo.previousAcquiredItem[i] = cpu[addrItems+i] end
		sessionInfo.previousLastProgressFrame = cpu2[addrLastProgressFrame]
		sessionInfo.acquiredItemQueue = {}
		sessionInfo.acquiredTimer = 0
		sessionInfo.acquiredItem = nil
		return
	end

	--キューを表示
	local minFrames = 30
	local maxFrames = 120

	sessionInfo.acquiredTimer = sessionInfo.acquiredTimer - 1
	if sessionInfo.acquiredTimer < 0 then
		sessionInfo.acquiredTimer = 0
		sessionInfo.acquiredItem = nil
	end
	if sessionInfo.acquiredTimer < maxFrames - minFrames and #sessionInfo.acquiredItemQueue ~= 0 then
		sessionInfo.acquiredItem = sessionInfo.acquiredItemQueue[1]
		table.remove( sessionInfo.acquiredItemQueue , 1 )
		item_log.get_item_textlog(sessionInfo.acquiredItem) -- by Append 20250819
		sessionInfo.acquiredTimer = maxFrames
	end
	if sessionInfo.acquiredItem then
		local str = itemName[sessionInfo.acquiredItem]
		if not str then str = string.format("Unknown : %03X",sessionInfo.acquiredItem) end
		Text.out(16,184,str,ew.RGB(255,255,255),ew.RGBA(0,0,0,150));
	end

	--進捗があったら獲得情報の変更分(0→1)を獲得したアイテムとする
	if sessionInfo.previousLastProgressFrame ~= cpu2[addrLastProgressFrame] then
		sessionInfo.previousLastProgressFrame = cpu2[addrLastProgressFrame]
		local acquiredItem = {}
		for i=0,cItems-1,1 do
			local cpuVal = cpu[addrItems+i]
			if sessionInfo.previousAcquiredItem[i] ~= cpuVal then
				local v0 = sessionInfo.previousAcquiredItem[i]
				local v1 = cpuVal
				for iB=0,7,1 do
					if v0 % 2 == 0 and v1 % 2 == 1 then
						local offset = i * 8 + iB
						acquiredItem[offset] = 1
					end
					v0 = v0 // 2
					v1 = v1 // 2
				end
				sessionInfo.previousAcquiredItem[i] = cpuVal
			end
		end
		--共有のための処理
		local shareInfo1 = cpu[addrMultiworldInfo[sessionInfo.currentGame]+1]
		local shareInfo2 = cpu[addrMultiworldInfo[sessionInfo.currentGame]+2]
		local shareInfo3 = cpu[addrMultiworldInfo[sessionInfo.currentGame]+3]
		local shareLifeUp = false
		local shareEnergyUp = false
		local shareArmor = false
		local shareSubTank = false
		local shareSpecialWeapon = false
		local shareStageKey = false
		local shareFinalWeapon = false
		local shareSigmaKey = false
		local shareUpgradeItem = false
		if ( shareInfo1 & 0x80 ) ~= 0 then shareLifeUp = true end 
		if ( shareInfo1 & 0x40 ) ~= 0 then shareEnergyUp = true end 
		if ( shareInfo1 & 0x20 ) ~= 0 then shareArmor = true end 
		if ( shareInfo1 & 0x10 ) ~= 0 then shareSubTank = true end 
--		if ( shareInfo1 & 0x08 ) ~= 0 then shareSpecialWeapon = true end 
--		if ( shareInfo1 & 0x04 ) ~= 0 then shareStageKey = true end 
		if ( shareInfo1 & 0x02 ) ~= 0 then shareFinalWeapon = true end 
		if ( shareInfo1 & 0x01 ) ~= 0 then shareSigmaKey = true end 
		if ( shareInfo2 & 0x80 ) ~= 0 then shareUpgradeItem = true end 
		--個数を維持するオプション
--		if ( shareInfo3 & 0x80 ) ~= 0 then shareLifeUp = false end 
--		if ( shareInfo3 & 0x40 ) ~= 0 then shareEnergyUp = false end 
--		if ( shareInfo3 & 0x01 ) ~= 0 then shareSigmaKey = false end 
		for i=0,0x2FF,1 do
			if acquiredItem[i] then
				local mergeItems = false
				local altItemNo = i % 0x100
				if altItemNo <= 0x0F then --ライフアップ
					if shareLifeUp then mergeItems = true end
				elseif altItemNo <= 0x1F then --武器エネルギーアップ
					if shareEnergyUp then mergeItems = true end
				elseif altItemNo <= 0x23 then --無し
					error "Unknown Item"
				elseif altItemNo <= 0x27 then --サブタンク
					if shareSubTank then mergeItems = true end
				elseif altItemNo <= 0x2F then --特殊武器/未実装
				elseif altItemNo <= 0x37 then --ステージの鍵/未実装
				elseif altItemNo <= 0x3F then --タイトル固有(共有なし)
				elseif altItemNo <= 0x4F then --シグマの鍵
					if shareSigmaKey then mergeItems = true end
				elseif altItemNo <= 0x50 then --最終兵器
					if shareFinalWeapon then mergeItems = true end
				elseif altItemNo <= 0x57 then --タイトル固有2(共有なし)
				elseif altItemNo <= 0x5F then --アーマーパーツ
					if shareArmor then mergeItems = true end
				elseif altItemNo <= 0x73 then --アップグレード
					if shareUpgradeItem then mergeItems = true end
				elseif altItemNo <= 0x77 then --無し
					error "Unknown Item"
				elseif altItemNo <= 0x7F then --回復アイテムなど
					acquiredItem[i] = nil
				elseif altItemNo <= 0xFE then --未使用
					error "Unknown Item"
				elseif altItemNo <= 0xFF then --NO ITEM
					acquiredItem[i] = nil
				end
				if mergeItems then
					acquiredItem[ altItemNo + 0x000 ] = nil
					acquiredItem[ altItemNo + 0x100 ] = nil
					acquiredItem[ altItemNo + 0x200 ] = nil
					acquiredItem[ altItemNo + 0x300 ] = 1
				end
			end
		end
		--キューに追加
		for k,v in pairs(acquiredItem) do
			table.insert( sessionInfo.acquiredItemQueue , k )
		end
	end


end
-------------------- 以下処理開始 -------------------------

if true then --Boot Sequence
	local BS = {} --Boot Sequence Table

	-- boot.smcの存在を確認
	local cBSTestExistence = {
		label = "Existence : " .. filename_boot,
		done = false,
		hasError = false,
		handler = function()
			if lu.fileExists(filename_boot) then return 1 end
			return -1
		end,
		arguments = nil,
	}
	table.insert(BS,cBSTestExistence)

	--boot.smcを読み込み状態を確認し、sessionInfoを更新
	local cBSTestBootSMC = {
		label = "Load and Test: " .. filename_boot,
		done = false,
		hasError = false,
		handler = function(offset,tbl)
			--ロードし1f待つ
			if not tbl.initialized then
				tbl.initialized = true
				client.openrom(filename_boot)
				return 0
			end

			local tmpTitle = 1
			--マルチワールド設定を読み、適切かどうかを確認
			local multiworldValue = cpu[addrMultiworldInfo[tmpTitle]]
			if multiworldValue < 0x80 then BS.errorInfo = "Error : Incorrect .smc(multiworld value)" ; return -1 end
			sessionInfo.games = (multiworldValue & 3)
			if sessionInfo.games <= 1 or sessionInfo.games >= 4 then BS.errorInfo = "Error : Incorrect .smc(game count)" ; return -1 end
			local games = 0
			for title=1,3,1 do
				if ( multiworldValue & (0x10 << (title-1)) ) ~= 0 then
					sessionInfo.randomizedGame[title] = true
					games = games + 1
					if not sessionInfo.currentGame then sessionInfo.currentGame = title end
				end
			end
			if sessionInfo.games ~= games then BS.errorInfo = "Error : Incorrect .smc(game count(2))" ; return -1 end

			--バイナリ識別情報が適切かどうか確認
			local binaryId = cpu[addrBinaryId[tmpTitle]]
			if binaryId < 0x80 then BS.errorInfo = "Error : Incorrect .smc(binaryId value)" ; return -1 end

			--ランダマイズパラメータが適切かどうか確認
			local param =  getParamOnROM(tmpTitle)
			if not param then BS.errorInfo = "Error : Incorrect .smc(param value)" ; return -1 end
			sessionInfo.param = param

			--テスト問題なし
			return 1
		end,
		arguments = nil,
	}
	table.insert(BS,cBSTestBootSMC)

	--コアのテスト
	local cCoreTest = {
		label = "Snes Core Test",
		done = false,
		hasError = false,
		handler = function(offset,tbl)
--emu.getluacore()が廃止され、代替とされているclient.get_lua_engine()も期待の動作をしない。
--よって、memory.getmemorydomainlist()の結果をコアの検出に使うというあまりにも愚かな方法用いる。

	local md_Snes9x = {"VRAM","CARTROM","Waterbox PageData",[0]="WRAM",}
	local md_Faust = {"CARTROM","VRAM","CGRAM","OAMLO","OAMHI","APURAM","Waterbox PageData",[0]="WRAM",}
	local md_Faust2 = {"CARTROM","APURAM","Waterbox PageData",[0]="WRAM",}
	local md_BSNES115 = {"WRAM","APURAM","VRAM","OBJECTS","CGRAM","System Bus","Waterbox PageData",[0]="CARTROM",}
	local md_BSNES = {"CARTROM","VRAM","OAM","CGRAM","APURAM","System Bus","Waterbox PageData",[0]="WRAM",}
--	print(lu.serialize(memory.getmemorydomainlist())) --上記、不毛なリストを作るためのデバッグライト

	local function cmpMD(cmp)
		local md = memory.getmemorydomainlist()
		if #md ~= #cmp then return false end
		for k,v in pairs(md) do
			local found = false
			for kc,vc in pairs(cmp) do
				if v == vc then found = true ; break end
			end
			if not found then return false end
		end
		return true
	end
	local coreName
	local process
	if cmpMD(md_Faust) or cmpMD(md_Faust2) then
		coreName = "Faust"
		process = 0
	elseif cmpMD(md_Snes9x) then
		coreName = "Snes9x"
		process = 1
	elseif cmpMD(md_BSNES) then
		coreName = "BSNES"
		process = 2
	elseif cmpMD(md_BSNES115) then
		coreName = "BSNESv115+"
		process = 2
	else
		coreName = "Unknown"
		process = 2
	end
	sessionInfo.core = coreName
	tbl.label = tbl.label .. " : Core : " .. coreName
	if process == 0 then
		tbl.label = tbl.label .. "(Recommended)"
		return 1
	elseif process == 1 then
		tbl.label = tbl.label .. "(Unsupported!!!)"
		BS.errorInfo = "Please select another core.\n('Config' > 'Preferred Cores' > 'SNES' > 'Faust')\nAnd reboot core.\n('Emulation' > 'Reboot Core')"
		return -1
	elseif process == 2 then
		tbl.label = tbl.label .. "(Not recommended)"
		tbl.status = "OK??"
		for i=240,0,-1 do
			local color = ew.RGB(255,255,255)
			if i%60 <= 30 then color = ew.RGB(255,96,96) end
			Text.out(16,16,"This core ("..coreName..") is NOT recommended.\nFaust core is recommended.",color,ew.RGBA(0,0,0,192))
			ew.frameadvance()
		end
		return 1
	end
	return -1
end,
		arguments = nil,
	}
	table.insert(BS,cCoreTest)

	--各ゲームを読み込み状態を確認しつつセーブステートを作ってもらう
	local function handler_testGameExistence(offset,tbl)
			if lu.fileExists(filename_game[tbl.arguments] ) then return 1 end
			return -1
	end
	local function handler_testGame(offset,tbl)
		if not tbl.initialized then
			tbl.initialized = true
			--初期化されていなければロードして1f待つ
			client.openrom(filename_game[tbl.arguments])
			return 0
		end

		--マルチワールド設定を読み、適切かどうかを確認
		local multiworldValue = cpu[addrMultiworldInfo[tbl.arguments]]
		if multiworldValue < 0x80 then BS.errorInfo = "Error : Incorrect .smc(multiworld value)" ; return -1 end
		if sessionInfo.games ~= (multiworldValue & 3) then BS.errorInfo = "Error : Incorrect .smc(game count)" ; return -1 end
		local games = 0
			for title=1,3,1 do
				if (( multiworldValue & (0x10 << (title-1)) ) ~= 0 ) ~= sessionInfo.randomizedGame[title] then
					BS.errorInfo = "Error : Incorrect .smc(game selection)"
					return -1
				end
			end

		--バイナリ識別情報が適切かどうか確認
		local binaryId = cpu[addrBinaryId[tbl.arguments]]
		if binaryId >= 0x80 then BS.errorInfo = "Error : Incorrect .smc(binaryId value)" ; return -1 end
		if (binaryId & 3) ~= tbl.arguments then BS.errorInfo = "Error : Incorrect .smc(binaryId value(title))" ; return -1 end

		--ランダマイズパラメータが適切かどうか確認
		local param =  getParamOnROM(tbl.arguments)
		if not param or sessionInfo.param ~= param then BS.errorInfo = "Error : Incorrect .smc(param value)" ; return -1 end

		--デフォルトアイテムデータを読み出す
		for i=0,0x1F,1 do
			sessionInfo.defaultItem[(tbl.arguments-1)*0x20+i] = cpu[addrDefaultItems[tbl.arguments]+i]
		end

		return 1
	end
	local function handler_createSaveState(offset,tbl)
		local filenameSS = getSaveStateFilename(tbl.arguments)
		if not tbl.initialized then
			tbl.initialized = true
			--既に同一コアのセーブステートがあればスキップ
			if sessionInfo.core == savestateCoreInfo[tbl.arguments] and lu.fileExists(filenameSS) then
				tbl.status = "SKIP"
				tbl.label = tbl.label .. "  Core : " .. sessionInfo.core
				return 1
			end
			BS.commonInfo = "Please \"GAME START\" with START button."
			return 0
		end
		local sv = receiveSynchronizingValue(tbl.arguments)
		sv = sv - 0x80
		if sv < 0 then
		elseif sv == cMS_saveState then
			savestate.save(filenameSS)
			savestateCoreInfo[tbl.arguments] = sessionInfo.core
			lu.saveTable(filenameSavestateCoreInfo,"savestateCoreInfo")
			tbl.label = tbl.label .. "  Core : " .. sessionInfo.core
			return 1
		else
			BS.errorInfo = "Failed : incorrect synchronizing value."
			return -1
		end
		return 0
	end
	local cBSTestGames = {
		label = nil,
		done = false,
		hasError = false,

		handler = function(offset,tbl)
			for title=1,3,1 do
				if sessionInfo.randomizedGame[title] then
					local newSequence = {}
					newSequence.label = "Existence : " .. filename_game[title] 
					newSequence.done = false
					newSequence.hasError = false
					newSequence.handler = handler_testGameExistence
					newSequence.arguments = title
					table.insert(BS,offset+1,newSequence)
					offset = offset + 1
				end
			end
			for title=1,3,1 do
				if sessionInfo.randomizedGame[title] then
					local newSequence = {}
					newSequence.label = "Load and Test : " .. filename_game[title] 
					newSequence.done = false
					newSequence.hasError = false
					newSequence.handler = handler_testGame
					newSequence.arguments = title
					table.insert(BS,offset+1,newSequence)
					offset = offset + 1

					local newSequence = {}
					newSequence.label = "Create Save State : " .. filename_game[title] 
					newSequence.done = false
					newSequence.hasError = false
					newSequence.handler = handler_createSaveState
					newSequence.arguments = title
					table.insert(BS,offset+1,newSequence)
					offset = offset + 1

				end
			end
			--次へ
			return 1
		end,
		arguments = nil,
	}
	table.insert(BS,cBSTestGames);
	--全てのテストが終了、スタート押下を待つ
	local cBSNoError = {
		label = nil,
		done = false,
		hasError = false,
		handler = function(offset,tbl)
			updateInput()
			if not tbl.initialized then
				tbl.initialized = true
				--ブートモードを起動して、スタートボタン押下を待つ
				client.openrom(filename_boot)
				BS.commonInfo = "\nPlease press [START] button."
				return 0
			end

			--スタートボタン押下で次へ
			if tPad.press("Start") then
				return 1
			end
			--セレクトボタンでオートセーブタイミング指定
			local strTblAutoSave = {"At Boss Select","Every 15 Seconds","Disabled"}
			if tPad.press("Select") then
				sessionSave.autoSave = sessionSave.autoSave + 1
				if sessionSave.autoSave > #strTblAutoSave then sessionSave.autoSave = 1 end
			end
			local strAutoSave = strTblAutoSave[sessionSave.autoSave]
			Text.out(16,200,"Auto Save[SELECT] : "..strAutoSave,ew.RGB(0,255,255),ew.RGBA(0,0,0,192))
			return 0
		end,
		arguments = nil,
	}
	table.insert(BS,cBSNoError);

	while true do
		local outY = 16
		local processed = false
		local order = 1
		Text.out(16,outY,"Boot Sequence",ew.RGB(255,255,255),ew.RGBA(0,0,0,192))
		outY = outY + 8
		for k,tbl in ipairs(BS) do
			--BSテーブル上で、最初に見つかった処理していないシーケンスに
			--エラーがなければ処理を行い、結果を書き込むか保留する。
			if not processed and not tbl.done then
				processed = true
				if not tbl.hasError then
					local rv = tbl.handler(k,tbl)
					if rv > 0 then
						tbl.done = true
						BS.commonInfo = nil
					elseif rv < 0 then
						tbl.hasError = true
						BS.commonInfo = nil
					end
				end
			end
			--リストを表示
			if tbl.label then
				local color = ew.RGB(255,255,255)
				if tbl.hasError then
					color = ew.RGB(255,64,64)
					if not tbl.status then tbl.status = "NG!!" end
				elseif tbl.done then
					color = ew.RGB(64,255,64)
					if not tbl.status then tbl.status = "OK  " end
				end
				local status = tbl.status
				if not status then status = "    " end
				local str = status .. "[" .. order .. "]" .. tbl.label
				order = order + 1
				Text.out(16,outY,str,color,ew.RGBA(0,0,0,192))
				outY = outY + 8
			end
		end
		if BS.errorInfo then
			Text.out(16,outY,BS.errorInfo,ew.RGB(255,64,64),ew.RGBA(0,0,0,192))
			outY = outY + 8
		elseif BS.commonInfo then
			Text.out(16,outY,BS.commonInfo,ew.RGB(64,255,64),ew.RGBA(0,0,0,192))
			outY = outY + 8
		end
		ew.frameadvance()
		--最後まで処理が行われなかったら終了
		if not processed then break end
	end
end

------------------------- ゲーム開始 -------------------------
	--print(lu.serialize(sessionInfo.defaultItem)) --デフォルトアイテムが適切に読み出されているか
	--ゲームをロード
	loadGame()
	quickInfo("Welcome to Route MatriX Randomizer!")
	--デフォルトアイテムのデータを出力
	for i=0,0x5F,1 do
		local tmp = sessionInfo.defaultItem[i]
		if tmp then
			cpu[addrItems+i] = cpu[addrItems+i] | tmp
		end
	end
	--ゲームのメインループ
while true do
	--同期変数(と呼んでいる変数)を読み、それに応じ処理を行う
	local sv = receiveSynchronizingValue(sessionInfo.currentGame)
	sv = sv - 0x80
	if sv < 0 then
	elseif sv == cMS_switchGame then switchGame(-1)
	elseif sv == cMS_switchGameL then switchGame(1)
	elseif sv == cMS_switchGameR then switchGame(2)
	elseif sv == cMS_switchGameLR then switchGame(3)
	elseif sv == cMS_saveState then
		cpu[addrSValue] = 0 --セーブステート採取タイミング
	elseif sv == cMS_queryClearStatus then
		updateSaveValue(false) --同期

		local allClear = true
		for title=1,3,1 do
			if sessionInfo.randomizedGame[title] and sessionSave.titleValue[title][addrClear[title]] < 0x80 then
				allClear = false
			end
		end
		local wv = 0
		if allClear then
			wv = 1
			if cpu4[addrClearFrames] == 0 then
				cpu4[addrClearFrames] = (cpu2[addrPlayFrames1] << 16 ) | cpu2[addrPlayFrames0]
				local str = "All Clear Time : " .. getHMMSS(cpu4[addrClearFrames])
				print(str)
				quickInfo(str)
			end
		else
			local strClearInfo = "Clear :"
			for title=1,3,1 do
				if sessionInfo.randomizedGame[title] then
					if sessionSave.titleValue[title][addrClear[title]] >= 0x80 then
						strClearInfo = strClearInfo .. " X" .. title
					else
						strClearInfo = strClearInfo .. " --"
					end
				end
			end
			quickInfo(strClearInfo,600)
			print(strClearInfo)
		end
		cpu[addrSValue] = wv
		updateSaveValue(false) --同期
	else
		error("Invalid command.")
	end

	--ヒント情報の同期
	synchronizeHintInfo()

	sessionInfo.frameCounter = sessionInfo.frameCounter + 1

	if true then --オートセーブ
		if sessionSave.autoSave == 2 and sessionInfo.frameCounter % (60*15) == 0 then
			sessionInfo.autoSavingIsReserved = true
		end
	end

	if true then
		local info = cpu[addrSInfo]
		if info == cMI_atBossSelect then
			infoAtBossSelect()
			if sessionSave.autoSave == 1 then updateSaveValue(false) end
		end
		cpu[addrSInfo] = 0
	end

	--クラッシュ対策/5fの間ゲームフレーム処理数がインクリメントされ続けた時のみセーブ(完全ではないがマシになる)
	if sessionInfo.autoSavingIsReserved then
		if not sessionInfo.framecounterLogForAutoSaving then sessionInfo.framecounterLogForAutoSaving = {} end
		sessionInfo.framecounterLogForAutoSaving[#sessionInfo.framecounterLogForAutoSaving+1] = cpu[addrGameFrameCounter[sessionInfo.currentGame]]

--		Text.out(16,200,lu.serialize(sessionInfo.framecounterLogForAutoSaving),ew.RGB(255,255,255),ew.RGBA(0,0,0,192)) --Debug Write
		local logSize = 5
		if #sessionInfo.framecounterLogForAutoSaving >= logSize then
			local doSaving = true
			for i=1,logSize-1,1 do
				if sessionInfo.framecounterLogForAutoSaving[i] ~= sessionInfo.framecounterLogForAutoSaving[i+1]-1 then
					doSaving = false
				end
			end
			if doSaving then
				sessionInfo.autoSavingIsReserved = false
				updateSaveValue(false)
			end
			sessionInfo.framecounterLogForAutoSaving = nil
		end
	end

	acquiredItemInfo()

	if sessionInfo.info then
		Text.out(16,200,sessionInfo.info,ew.RGB(255,255,255),ew.RGBA(0,0,0,192))
		if not sessionInfo.infoTimer then sessionInfo.infoTimer = 300 end
		sessionInfo.infoTimer = sessionInfo.infoTimer - 1
		if sessionInfo.infoTimer <= 0 then
			sessionInfo.info = nil
		end
	end
	ew.frameadvance()
	ew.ui.pixel(0,0,ew.RGBA(0,0,0,1))
end
