module(..., package.seeall)
require"xselec"

local function iter(t, filter)
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
		return make_elem(item, self)
	end, state
end

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
	mt.val = function(t, val)
		if type(t.node[1]) ~= 'string' then return end
		if val then
			rawset(t.node, 1, tostring(val))
		else
			return tostring(t.node[1])
		end
	end
	mt.iter = iter

	mt.__call = function(t, filter) 
		local result = {}
		for i, v in ipairs(t.node(filter)) do
			table.insert(result, make_elem(v))
		end
		return result
	end
	return mt
end

local mt_elem = forward_attr()

function make_elem(node, mt)
	local elem = {node = xselec.make_selectable(node)}
	local mt_ = mt or mt_elem
	setmetatable(elem, mt_)
	return elem
end

local function cook_elems(doc, selector, target, mt)
	for e in doc.node(selector):iter() do
		local elem = make_elem(e, mt)
		table.insert(target, elem)
		target[e.attr.Id] = elem
	end
end

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
		if style.EngName then
			target_list[style.EngName] = style
		end
	end
	return para_styles, char_styles
end

function load(filename)
	local xml, err = xselec.load_from_file(filename)
	if xml == nil then
		return nil, err
	end

	local doc = make_elem(xml)
	doc.filename = filename
	doc.save = function(self, filename)
		filename = filename or self.filename
		io.open(filename,'wb'):write(self.node:toxml())
	end

	doc.output = function(self, puts)
		puts = puts or io.write
		self.node:output(puts)
	end	

	doc.paras = function(self)
		local result = {}
		for p in self.node'BODY P':iter() do
			table.insert(result, make_elem(p))
		end
		return result
	end

	doc.strings = function(self)
		local result = {}
		local charmap = {TAB = '\t', LINEBREAK = '\n', HYPEN = '-', 
			NBSPACE = string.char(160)
		}
		for _, p in ipairs(doc:paras()) do
			local first_c = true
			local last_c
			for t in p:iter'TEXT' do
				for c in t:iter'CHAR' do for i, v in ipairs(c.node) do
					local str = ''
					local node
					if type(v) == 'table' and v.tag then
						str = charmap[v.tag] or ''
						node = v
					else
						str = v
					end

					local item = {
						char = c, para = p, text = t, 
						str = str, node = node
					}
					item.first = first_c
					first_c = nil
					last_c = item
					table.insert(result, item)
				end end
			end
			if last_c then last_c.last = true end
		end
		return result
	end

	doc.iter = iter

	doc.fonts = get_fonts(doc)
	doc.para_shapes, doc.char_shapes = get_shapes(doc)
	doc.para_styles, doc.char_styles = get_styles(doc)
	return doc
end
