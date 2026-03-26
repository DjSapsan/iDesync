local table = require 'ext.table'
local string = require 'ext.string'
local assert = require 'ext.assert'
local Tokenizer = require 'parser.base.tokenizer'

local LuaTokenizer = Tokenizer:subclass()

--[[
NOTICE this only needs to be initialized once per tokenizer, not per-data-source
however at the moment it does need to be initialized once-per-version (as the extra arg to Tokenizer)
maybe I should move it to static initialization and move version-based stuff to subclasses' static-init?

So why 'symbols' vs 'keywords' ?
'Keywords' consist of valid names (names like variables functions etc use)
while 'symbols' consist of everything else. (can symbols contain letters that names can use? at the moment they do not.)
For this reason, when parsing, keywords need separated spaces, while symbols do not (except for distinguishing between various-sized symbols, i.e. < < vs <<).
--]]
function LuaTokenizer:initSymbolsAndKeywords(version, useluajit)
	self.symbols = table(self.symbols)
	self.keywords = table(self.keywords):setmetatable(nil)

	-- store later for parseHexNumber
	self.version = assert(version)
	self.useluajit = useluajit

	for w in ([[... .. == ~= <= >= + - * / % ^ # < > = ( ) { } [ ] ; : , .]]):gmatch('%S+') do
		self.symbols:insert(w)
	end

	for w in ([[and break do else elseif end false for function if in local nil not or repeat return then true until while]]):gmatch('%S+') do
		self.keywords[w] = true
	end

	-- TODO this will break because luajit doesn't care about versions
	-- if I use a load-test, the ext.load shim layer will break
	-- if I use a load('goto=true') test without ext.load then load() doens't accept strings for 5.1 when the goto isn't a keyword, so I might as well just test if load can load any string ...
	-- TODO separate language features from versions and put all the language options in a ctor table somewhere
	do--if version >= '5.2' then
		self.symbols:insert'::'	-- for labels .. make sure you insert it before ::
		self.keywords['goto'] = true
	end
	
	if version >= '5.3' then
		self.symbols:insert'//'
		self.symbols:insert'~'
		self.symbols:insert'&'
		self.symbols:insert'|'
		self.symbols:insert'<<'
		self.symbols:insert'>>'
	end
end

-- Lua-specific '' or "" single-line quote-strings with escape-codes
function LuaTokenizer:parseQuoteString()
	local r = self.r
	if r:canbe'["\']' then
		local quote = r.lasttoken
		local s = table()
		while true do
			r:seekpast'.'
			if r.lasttoken == quote then break end
			if r:done() then error{msg="unfinished string"} end
			if r.lasttoken == '\\' then
				local esc = r:canbe'.'
				local escapeCodes = {a='\a', b='\b', f='\f', n='\n', r='\r', t='\t', v='\v', ['\\']='\\', ['"']='"', ["'"]="'", ['0']='\0', ['\r']='\n', ['\n']='\n'}
				local escapeCode = escapeCodes[esc]
				if escapeCode then
					s:insert(escapeCode)
				elseif esc == 'x' and self.version >= '5.2' then
					esc = r:mustbe'%x' .. r:mustbe'%x'
					s:insert(string.char(tonumber(esc, 16)))
				elseif esc == 'u' and self.version >= '5.3' then
					r:mustbe'{'
					local code = 0
					while true do
						local ch = r:canbe'%x'
						if not ch then break end
						code = code * 16 + tonumber(ch, 16)
					end
					r:mustbe'}'

					local bit = bit32 or require 'bit'
					if code < 0x80 then
						s:insert(string.char(code))
					elseif code < 0x800 then
						s:insert(
							string.char(bit.bor(0xc0, bit.band(0x1f, bit.rshift(code, 6))))
							.. string.char(bit.bor(0x80, bit.band(0x3f, code)))
						)
					elseif code < 0x10000 then
						s:insert(
							string.char(bit.bor(0xe0, bit.band(0x0f, bit.rshift(code, 12))))
							.. string.char(bit.bor(0x80, bit.band(0x3f, bit.rshift(code, 6))))
							.. string.char(bit.bor(0x80, bit.band(0x3f, code)))
						)
					else
						s:insert(
							string.char(bit.bor(0xf0, bit.band(0x07, bit.rshift(code, 18))))
							.. string.char(bit.bor(0x80, bit.band(0x3f, bit.rshift(code, 12))))
							.. string.char(bit.bor(0x80, bit.band(0x3f, bit.rshift(code, 6))))
							.. string.char(bit.bor(0x80, bit.band(0x3f, code)))
						)
					end
				elseif esc:match('%d') then
					-- can read up to three
					if r:canbe'%d' then esc = esc .. r.lasttoken end
					if r:canbe'%d' then esc = esc .. r.lasttoken end
					s:insert(string.char(tonumber(esc)))
				else
					if self.version >= '5.2' then
						error{msg="invalid escape sequence "..esc}
					end
				end
			else
				s:insert(r.lasttoken)
			end
		end
		coroutine.yield(s:concat(), 'string')
		return true
	end
end

function LuaTokenizer:parseHexNumber(...)
	local r = self.r
	-- if version is 5.2 then allow decimals in hex #'s, and use 'p's instead of 'e's for exponents
	if self.version >= '5.2' then
		-- TODO this looks like the float-parse code below (but with e+- <-> p+-) but meh I'm lazy so I just copied it.
		local token = r:canbe'[%.%da-fA-F]+'
		local numdots = #token:gsub('[^%.]','')
		assert.le(numdots, 1, {msg='malformed number'})
		local n = table{'0x', token}
		if r:canbe'p' then
			n:insert(r.lasttoken)
			-- fun fact, while the hex float can include hex digits, its 'p+-' exponent must be in decimal.
			n:insert(r:mustbe('[%+%-]%d+', 'malformed number'))
		elseif numdots == 0 and self.useluajit then
			if r:canbe'LL' then
				n:insert'LL'
			elseif r:canbe'ULL' then
				n:insert'ULL'
			end
		end
		coroutine.yield(n:concat(), 'number')
	else
		--return LuaTokenizer.super.parseHexNumber(self, ...)
		local token = r:mustbe('[%da-fA-F]+', 'malformed number')
		local n = table{'0x', token}
		if self.useluajit then
			if r:canbe'LL' then
				n:insert'LL'
			elseif r:canbe'ULL' then
				n:insert'ULL'
			end
		end
		coroutine.yield(n:concat(), 'number')
	end
end

function LuaTokenizer:parseDecNumber()
	local r = self.r
	local token = r:canbe'[%.%d]+'
	local numdots = #token:gsub('[^%.]','')
	assert.le(numdots, 1, {msg='malformed number'})
	local n = table{token}
	if r:canbe'e' then
		n:insert(r.lasttoken)
		n:insert(r:mustbe('[%+%-]%d+', 'malformed number'))
	elseif numdots == 0 and self.useluajit then
		if r:canbe'LL' then
			n:insert'LL'
		elseif r:canbe'ULL' then
			n:insert'ULL'
		end
	end
	coroutine.yield(n:concat(), 'number')
end

return LuaTokenizer
