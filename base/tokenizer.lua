local table = require 'ext.table'
local string = require 'ext.string'
local class = require 'ext.class'
local assert = require 'ext.assert'
local DataReader = require 'parser.base.datareader'

local Tokenizer = class()

function Tokenizer:initSymbolsAndKeywords(...)
end

function Tokenizer:init(data, ...)
	self:initSymbolsAndKeywords(...)

	self.r = DataReader(data)
	self.gettokenthread = coroutine.create(function()
		local r = self.r

		while not r:done() do
			self:skipWhiteSpaces()
			if r:done() then break end

			if self:parseComment() then
			elseif self:parseString() then
			elseif self:parseName() then
			elseif self:parseNumber() then
			elseif self:parseSymbol() then
			else
				error{msg="unknown token "..r.data:sub(r.index)}
			end
		end
	end)
end

function Tokenizer:skipWhiteSpaces()
	local r = self.r
	r:canbe'%s+'
---DEBUG(parser.base.tokenizer): if r.lasttoken then print('read space ['..(r.index-#r.lasttoken)..','..r.index..']: '..r.lasttoken) end
end

-- Lua-specific comments (tho changing the comment symbol is easy ...)
Tokenizer.singleLineComment = string.patescape'--'
function Tokenizer:parseComment()
	local r = self.r
	if r:canbe(self.singleLineComment) then
local start = r.index - #r.lasttoken
		-- read block comment if it exists
		if not self:readblock() then
			-- read line otherwise
			if not r:seekpast'\n' then
				r:seekpast'$'
			end
		end
		--local commentstr = r.data:sub(start, r.index-1)
		-- TODO how to insert comments into the AST?  should they be their own nodes?
		-- should all whitespace be its own node, so the original code text can be reconstructed exactly?
		--coroutine.yield(commentstr, 'comment')
---DEBUG(parser.base.tokenizer): print('read comment ['..start..','..(r.index-1)..']:'..commentstr)
		return true
	end
end

function Tokenizer:parseString()
	if self:parseBlockString() then return true end
	if self:parseQuoteString() then return true end
end

-- Lua-specific block strings
function Tokenizer:parseBlockString()
	local r = self.r
	if self:readblock() then
---DEBUG(parser.base.tokenizer): print('read multi-line string ['..(r.index-#r.lasttoken)..','..r.index..']: '..r.lasttoken)
		coroutine.yield(r.lasttoken, 'string')
		return true
	end
end

-- Lua-specific [=*[ ... ]=*] block syntax (used by block strings and block comments)
function Tokenizer:readblock()
	local r = self.r
	if not r:canbe('%[=*%[') then return end
	local eq = assert(r.lasttoken:match('^%[(=*)%[$'))
	r:canbe'\n'	-- if the first character is a newline then skip it
	local start = r.index
	if not r:seekpast('%]'..eq..'%]') then
		error{msg="expected closing block"}
	end
	r.lasttoken = r.data:sub(start, r.index - #r.lasttoken - 1)
	return r.lasttoken
end

-- override in subclass for language-specific quote string parsing
function Tokenizer:parseQuoteString()
end

-- C names
function Tokenizer:parseName()
	local r = self.r
	if r:canbe'[%a_][%w_]*' then	-- name
---DEBUG(parser.base.tokenizer): print('read name ['..(r.index-#r.lasttoken)..', '..r.index..']: '..r.lasttoken)
		coroutine.yield(r.lasttoken, self.keywords[r.lasttoken] and 'keyword' or 'name')
		return true
	end
end

function Tokenizer:parseNumber()
	local r = self.r
	if r.data:match('^[%.%d]', r.index) -- if it's a decimal or a number...
	and (r.data:match('^%d', r.index)	-- then, if it's a number it's good
	or r.data:match('^%.%d', r.index))	-- or if it's a decimal then if it has a number following it then it's good ...
	then 								-- otherwise I want it to continue to the next 'else'
		-- lua doesn't consider the - to be a part of the number literal
		-- instead, it parses it as a unary - and then possibly optimizes it into the literal during ast optimization
---DEBUG(parser.base.tokenizer): local start = r.index
		if r:canbe'0[xX]' then
			self:parseHexNumber()
		else
			self:parseDecNumber()
		end
---DEBUG(parser.base.tokenizer): print('read number ['..start..', '..r.index..']: '..r.data:sub(start, r.index-1))
		return true
	end
end

function Tokenizer:parseHexNumber()
	local r = self.r
	local token = r:mustbe('[%da-fA-F]+', 'malformed number')
	coroutine.yield('0x'..token, 'number')
end

function Tokenizer:parseDecNumber()
	local r = self.r
	local token = r:canbe'[%.%d]+'
	assert.le(#token:gsub('[^%.]',''), 1, 'malformed number')
	local n = table{token}
	if r:canbe'e' then
		n:insert(r.lasttoken)
		n:insert(r:mustbe('[%+%-]%d+', 'malformed number'))
	end
	coroutine.yield(n:concat(), 'number')
end

function Tokenizer:parseSymbol()
	local r = self.r
	-- see if it matches any symbols
	for _,symbol in ipairs(self.symbols) do
		if r:canbe(string.patescape(symbol)) then
---DEBUG(parser.base.tokenizer): print('read symbol ['..(r.index-#r.lasttoken)..','..r.index..']: '..r.lasttoken)
			coroutine.yield(r.lasttoken, 'symbol')
			return true
		end
	end
end

-- separate this in case someone has to modify the tokenizer symbols and keywords before starting
function Tokenizer:start()
	-- TODO provide tokenizer the AST namespace and have it build the tokens (and keywords?) here automatically
	self.symbols = self.symbols:mapi(function(v,k) return true, v end):keys()
	-- arrange symbols from largest to smallest
	self.symbols:sort(function(a,b) return #a > #b end)
	self:consume()
	self:consume()
end

Tokenizer.locHistorySize = 4

function Tokenizer:consume()
	if not self.locHistory then
		self.locHistory = {}
	end
	table.insert(self.locHistory, 1, {
		index = self.r.index,
		tokenIndex = #self.r.tokenhistory + 1,
	})
	-- trim to configured size
	for i = self.locHistorySize + 1, #self.locHistory do
		self.locHistory[i] = nil
	end

	self.token = self.nexttoken
	self.tokentype = self.nexttokentype
	if coroutine.status(self.gettokenthread) == 'dead' then
		self.nexttoken = nil
		self.nexttokentype = nil
		-- done = true
		return
	end
	local status, nexttoken, nexttokentype = coroutine.resume(self.gettokenthread)
	-- detect errors
	if not status then
		local err = nexttoken
		error{
			msg = err,
			token = self.token,
			tokentype = self.tokentype,
			pos = self:getpos(),
			traceback = debug.traceback(self.gettokenthread),
		}
	end
	self.nexttoken = nexttoken
	self.nexttokentype = nexttokentype
end

function Tokenizer:getpos()
	return 'line '..self.r.line
		..' col '..self.r.col
		..' code "'..self.r.data:sub(self.r.index):match'^[^\n]*'..'"'
end

-- return the span location; 'back' selects how far back in history (default 2)
function Tokenizer:getloc(back)
	back = back or 2
	local entry = self.locHistory and self.locHistory[back]
	return {
		line = self.r.line,
		col = self.r.col,
		index = entry and entry.index,
		tokenIndex = entry and entry.tokenIndex,
	}
end

return Tokenizer
