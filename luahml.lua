local xselec = require"xselec"

local mt_common, mt_para, mt_char
	, make_elem, iter


---------------------------------------
-- 모든 요소의 기본 메서드들
---------------------------------------

local function forward_attr(mt)
	mt = mt or {}
	mt.__index = function(t, key)
		local val = rawget(mt, key)
		if val then return val end
		val = rawget(t, key)
		if val then return val end

		local node = rawget(t, 'node')

		if node then
			if type(node[key]) == 'table' and node[key].tag then
				return make_elem(node[key])
			else
				return node.attr[key]
			end
		end
	end
	mt.__newindex = function(t, key, val)
		local v = rawget(t, key)
		if v ~= nil then
			rawset(t, key, val)
		elseif type(key) == 'string' and key:find('^%u') then
			if rawget(t.node.attr, key) == nil then
				table.insert(t.node.attr, key)
			end
			rawset(t.node.attr, key, val)
		else
			rawset(t, key, val)
		end
	end

	mt.__call = function(t, filter) 
		local result = {}
		for i, v in ipairs(t.node(filter)) do
			table.insert(result, make_elem(v))
		end
		return result
	end

	mt.val = function(t, val)
		if type(t.node[1]) ~= 'string' then return end
		if val then
			rawset(t.node, 1, tostring(val))
		else
			return tostring(t.node[1])
		end
	end
	mt.iter = iter

	return mt
end

iter = function(t, filter)
	local state = { index = 0}
	if filter then
		state.items = t.node(filter)
	else
		state.items = t.node
	end
	return function(state)
		local item
		while true do
			state.index = state.index + 1
			if state.index > #(state.items) then return end
			item = rawget(state.items, state.index)
			if item.tag then break end
		end
		return make_elem(item)
	end, state
end

mt_common = forward_attr()

make_elem = function(node, mt)
	local metatable_map = {P = mt_para, CHAR = mt_char}
	local elem = {node = xselec.make_selectable(node)}
	local mt_ = mt or metatable_map[node.tag] or mt_common
	setmetatable(elem, mt_)
	return elem
end

-- P 요소용 메서드
mt_para = forward_attr()

mt_para.append = function(self, para)
	table.insert(self.section.node, self.nth+1, para)
end

mt_para.prepend = function(self, para)
	table.insert(self.section.node, self.nth, para)
	return make_elem(para)
end

-- CHAR용 메서드
mt_char = forward_attr()
mt_char.val = function(elem, str)
	local charmap = {TAB = '\t', LINEBREAK = '\n',
			NBSPACE = string.char(160)
	}

	if str then
		for k, v in pairs(charmap) do
			str = str:gsub(v, '<' .. k .. '/>')
		end
		local nodes = xselec.load_from_string('<DUMMY>' .. str .. '</DUMMY>')
		for i, v in ipairs(nodes) do
			elem.node[i] = v
		end
		elem.node[#nodes+1] = nil
		return
	else
		local str = ''
		for i, v in ipairs(elem.node) do
			if type(v) == 'table' and v.tag then
				local cd = charmap[v.tag] or xselec.make_selectable(v):toxml()
				str = str .. cd
				
			else
				str = str .. v
			end
		end
		return str
	end
end

---------------------------------------------
-- 기타 함수들
---------------------------------------------
local function get_fonts(doc)
	local fonts = {}
	for e in doc:iter'HEAD MAPPINGTABLE FONT' do
		table.insert(fonts, e)
		fonts[e.Id] = e
	end
	return fonts
end

local function get_shapes(doc)
	local para_shapes, char_shapes = {}, {}

	for e in doc:iter'HEAD PARASHAPE' do
		e.margin = make_elem(e.node'PARAMARGIN'[1])
		e.border = make_elem(e.node'PARABORDER'[1])
	end

	for e in doc:iter'HEAD CHARSHAP' do
		e.font = {}
		local fontid = e'FONTID'[1]
		for i, v in ipairs(fontid.attr) do
			local font_lang = fontid.attr[i]
			e.font[font_lang] = doc.fonts[fontid.attr[font_lang]]
		end
	end	
	return para_shapes, char_shapes
end


local function Style(node,doc)
	local elem = make_elem(node)
	if node.attr.ParaShape then
		elem.para_shape = doc.para_shapes[node.attr.ParaShape]
	end
	if node.attr.CharShape then
		elem.char_shape = doc.char_shapes[node.attr.CharShape]
	end
	elem.Id = node.attr.Id
	return elem
end

local function get_styles(doc)
	local styles = doc.node'HEAD>MAPPINGTABLE>STYLELIST>STYLE'
	local para_styles, char_styles = {doc=doc}, {doc=doc}
	for node in styles:iter() do
		if node.attr.Type == 'Para' then
			target_list = para_styles
		else
			target_list = char_styles
		end
		local style = Style(node, doc)
		table.insert(target_list, style)
		target_list[style.Name] = style
		target_list[style.Id] = style
		if style.EngName then
			target_list[style.EngName] = style
		end
	end
	return para_styles, char_styles
end

local function get_chars(doc)
	local result = {}
	for _, p in ipairs(doc:get_paras()) do
		local first_c = true
		local last_c
		for t in p:iter'TEXT' do
			local item
			for c in t:iter'CHAR' do
				item = make_elem(c.node)
				item.text = t
				item.para = p
				item.first = first_c
				first_c = nil
				last_c = item
				table.insert(result, item)
			end
		end
		if last_c then last_c.last = true end
	end
	return result
end

local function get_paras(doc)
	local result = {}
	for s in doc.node'BODY SECTION':iter() do
		for i, p in ipairs(s) do
			local elem = make_elem(p, mt_paras)
			elem.section = make_elem(s)
			elem.nth = i
			table.insert(result, elem)
		end
	end
	return result
end

local function load(filename)
	local xml, err = xselec.load_from_file(filename)
	if xml == nil then
		return nil, err
	end

	local doc = make_elem(xml)

	-- HML 문서 객체의 속성, 메서드
	doc.iter = iter

	doc.filename = filename

	doc.para_shapes, doc.char_shapes = get_shapes(doc)
	doc.para_styles, doc.char_styles = get_styles(doc)

	doc.save = function(self, filename)
		filename = filename or self.filename
		io.open(filename,'wb'):write(self.node:toxml())
	end

	doc.output = function(self, puts)
		puts = puts or io.write
		self.node:output(puts)
	end	

	doc.get_paras = get_paras
	doc.get_chars = get_chars

	return doc
end

-- 모듈 인터페이스 --
return {
	load = load
	, make_elem = make_elem
}
