require"lxp.lom"

local function escape_xml_specials(str)
	str = string.gsub(str, '&', '&amp;')
	str = string.gsub(str, '<', '&lt;')
	str = string.gsub(str, '>', '&gt;')
	str = string.gsub(str, '"', '&quot;')
	return str
end

local function output_tree(node, puts, visited)
	visited = visited or {}
	puts = puts or io.write
	if node.preamble then puts(node.preamble) end
	if type(node) ~= 'table' then
		--puts(escape_xml_specials(node))
		puts(node)
	elseif type(node) == 'table' and not node.removed and node.tag then
		if visited[node] then return end -- 무한 루프 방지
		visited[node]=true
		puts('<'..node.tag)
		if (node.attr) then
			for i, name in ipairs(node.attr) do
				local v = node.attr[name]
				if type(v) == 'string' then
					puts(' ' .. name .. '="')
					puts(v .. '"')
				end
			end
		end
		if (#node==0) then
			puts('/>')
		else
			puts('>')
			for i, v in ipairs(node) do
				output_tree(v, puts, visited)
			end
			puts('</'..node.tag..'>')
		end
	end
end

local mt = {} -- 메서드들을 담은 메타테이블. 구체적인 정의는 아래에서.

local function make_selectable(t)
	setmetatable(t, mt)
	return t
end

local function get_target(t)
	if t.query_result then
		return t[1] or {attr={}}
	else
		return t or {attr={}}
	end
end

mt.__index = function(self, key)
	local val = rawget(mt, key)
	if val then return val end

	if rawget(self, 'query_result') and type(key) ~= 'number' then
		return rawget(rawget(self, 1), key)
	end

	return rawget(self, key)
end

mt.get = function(self, index)
	if not self.query_result then return end
	if type(index) == 'number' and index > 0 and index <= #self then
		return make_selectable(rawget(self, index))
	end
end

mt.text = function(self, val)
	local visited = {}
	local function get_text(t)
		if t.tag and visited[t] then return '' end
		visited[t] = true
		local result = ''
		for i, v in ipairs(t) do
			if type(v) == 'string' then
				result = result .. v
			elseif type(v) == 'table' then
				result = result .. get_text(v)
			end
		end
		return result
	end
	local target = get_target(self)
	if val then
		target[1] = val
		target[2] = nil
	else
		return get_text(target)
	end
end

mt.Attr = function(self, name, value)
	local elem = get_target(self)
	
	if value then
		elem.attr[name] = value
		return value
	end

	return elem.attr[name]
end

mt.Tag = function(self, value)
	local elem = get_target(self)
	
	if value then
		elem.tag = value
		return value
	end

	return elem.tag
end

mt.Id = function(self, value)
	local elem = get_target(self)
	
	if value then
		elem.attr['id'] = value
		return value
	end

	return elem.attr['id']
end

mt.Class = function(self, value)
	local elem = get_target(self)
	
	if value then
		elem.attr['class'] = value
		return value
	end

	return elem.attr['class']
end

mt.each = function(self, f)
	if not self.query_result then return end
	for i, v in ipairs(self) do
		f(make_selectable(v))
	end
end

mt.iter = function(self)
	local state = {index=0}
    return function(state)
    	state.index = state.index + 1
    	if state.index > #self then return end
    	return make_selectable(rawget(self, state.index))
    end, state
end

local function find_elems(node, pred, norecurse, result, visited)
	if type(node) ~= 'table' then return end
	for i, e in ipairs(node) do
		if type(e) == 'table' and e.tag and not e.removed then
			if not visited[e] and pred(e) then
				table.insert(result, e)
				visited[e] = true
			end
		end
		if not norecurse then
			find_elems(e, pred, norecurse, result, visited)
		end
	end
end

local function search_node(node, pred, norecurse)
	local result = {}
	local visited = {}
	find_elems(node, pred, norecurse, result, visited)
	return result
end

local function search_children(node, pred, norecurse)
	local result = {}
	local visited = {}
	for i, e in ipairs(node) do
		find_elems(e, pred, norecurse, result, visited)
	end
	return result
end

local pred_tag = function(name) 
	return function(e) return e.tag == name end
end

local pred_attr_exact = function(name, value)
	if value then
		return function(e)
			return e.attr[name] and e.attr[name] == value
		end
	end

	return function(e)
		return e.attr[name] ~= nil
	end
end

local pred_attr_included = function(name, value)
	return function(e)
		if e.attr[name] then
			for w in e.attr[name]:gmatch('([%a%d-_]+)') do
				if w == value then return true end
			end
		end
		return false
	end
end

mt.by_attr = function(self, name, value)
	local result= search_node(self, pred_attr_exact(name, vaule))
	result.query_result = true
	return make_selectable(result)
end

mt.with_attr = function(self, name, value)
	local result= search_node(self, pred_attr_exact(name, vaule), true)
	result.query_result = true
	return make_selectable(result)
end

mt.__call = function(self, selector)
	local target = self
	local search_func = search_node
	local result = nil
	local norecurse = false
	local conn, prefix, key

	local function parse_selector(str)
		local i, j, conn = str:find('^([ ,>]+)([^ ,>]*)')

		if conn then
			str = str:sub(#conn+1)
			if conn:find('^ +$') then
				conn = ' '
			else
				conn = conn:gsub(' ', '')
			end
		end

	   	local i, j, p, m = str:find('([.#%[]?)([%a%d-_]+)')
	   	if i then
	   		return (conn or ''), (p or ''), m, str:sub(j+1)
	   	end
	end


	local function get_attr_pred(key, str)
		local i, j, op = str:find('%s*([|*~$!^]?)(=)%s*')

		local pred

		if i == nil then
			pred = function(e)
				return e.attr[key] ~= nil
			end
		else
			str = str:sub(j+1)
			i, j, val = str:find('["\']?([^"\'%]]+)["\']?]')
			if j then str = str:sub(j+1) end
			if op == '' then
				pred = function(e)
					return e.attr[key] and e.attr[key] == val
				end
			elseif op == '!' then
				pred = function(e)
					return not e.attr[key] or e.attr[key] ~= val
				end
			elseif op == '~' then
				pred = pred_attr_included(key, val)
			else
				pattern = val:gsub('[%^$%(%)%%.%[%]*+-?]', '%%%1')
				-- see http://api.jquery.com/category/selectors/
				if op == '^' then
					pattern = '^' .. pattern
				elseif op == '$' then
					pattern = pattern .. '$'
				elseif op == '|' then
					pattern = '^' .. pattern .. '%-?'
				elseif op ~= '*' then
					pattern = '<' -- impossible match in xml
				end

				pred = function(e)
					return e.attr[key] and e.attr[key]:find(pattern)
				end
			end
		end
		return pred, str
	end

	local accum = {}

	selector = selector:gsub('^ +', '')
	is_first = true
	while selector do
		conn, prefix, key, selector = parse_selector(selector)

		if conn == '>' then
			target = result
			norecurse = true
			search_func = search_children
		elseif conn == ',' then
			for i, v in ipairs(result) do table.insert(accum, v) end
			target = self
			search_func = search_node
		elseif conn == ' ' then
			target = result
			search_func = search_children
		end

		if prefix == '' then
			pred = pred_tag(key)
		else
			if conn == '' and not is_first then
				target = result
				norecurse = true
				search_func = search_node
			end

			if prefix == '.' then
				pred = pred_attr_included('class', key)
			elseif prefix == '#' then
				pred = pred_attr_exact('id', key)
			elseif prefix == '[' then
				pred, selector = get_attr_pred(key, selector)
			end
		end

		result = search_func(target, pred, norecurse)
		--print(m, #result, target[1].tag)
		is_first = false
	end

	if (#accum > 0) then
		for i, v in ipairs(result) do table.insert(accum, v) end
		result = accum
	end

	result.query_result = true
	return make_selectable(result)
end

mt.remove = function(self)
	self.removed = true
end

mt.output = function(self, puts)
	output_tree(self, puts)
end

mt.toxml = function(self, puts)
	local lines = {}
	local function puts(str)
		table.insert(lines, str)
	end
	
	output_tree(self, puts)
	return table.concat(lines)
end

local function get_preamble(str)
	local i = string.find(str, '%<[^!?]')
	if i then
		return string.sub(str, 1, i-1)
	end
end

local function reserve_entities(str)
	return str:gsub('&', '&amp;')
end

local function load_from_string(str)
	str = reserve_entities(str)
	local preamble = get_preamble(str)
	local t, err = lxp.lom.parse(str)
	if t then
		t.preamble = preamble
		return make_selectable(t)
	else
		return nil, err
	end
end

local function load_from_file(filename)
	local f, err = io.open(filename,'rb')
	if f then
		return load_from_string(f:read'*a')
	else
		return nil, err
	end
end

local function regex_pattern(s)
	return {pattern=s}
end

-- interface --
return {
	load_from_string = load_from_string
	, load_from_file = load_from_file
	, make_selectable = make_selectable
	, regex_pattern = regex_pattern
}
