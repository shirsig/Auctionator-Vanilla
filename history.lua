local private, public = {}, {}
Aux.history = public

private.PUSH_INTERVAL = 57600
private.NEW_RECORD = '0#0##'

function private.load_data()
	local dataset = Aux.persistence.load_dataset()
	dataset.history = dataset.history or { next_push = time() + private.PUSH_INTERVAL, item_data = {} }
	return dataset.history
end

function private.read_record(item_key)
	local data = private.load_data()
	local record = Aux.persistence.deserialize(data.item_data[item_key] or private.NEW_RECORD, '#')
	return {
		auction_count = tonumber(record[1]),
		day_count = tonumber(record[2]),
		balanced_list = Aux.util.map(Aux.persistence.deserialize(record[3], ';'), function(value)
			return tonumber(value)
		end),
		histogram = Aux.util.map(Aux.persistence.deserialize(record[4], ';', 'x'), function(value)
			return tonumber(value)
		end),
	}
end

function private.write_record(item_key, record)
	local data = private.load_data()
	data.item_data[item_key] = Aux.persistence.serialize({
		record.auction_count,
		record.day_count,
		Aux.persistence.serialize(record.balanced_list, ';'),
		Aux.persistence.serialize(record.histogram, ';', 'x'),
	},'#')
end

function public.process_auction(auction_info)

	if auction_info.buyout_price == 0 then
		return
	end

	local data = private.load_data()

	if data.next_push < time() then
		private.push_data()
	end

	local buyout = auction_info.buyout_price / auction_info.aux_quantity

	local item_record = private.read_record(auction_info.item_key)

	item_record.auction_count = item_record.auction_count + 1

	for i=1,225 do
		item_record.histogram[i] = item_record.histogram[i] or 0
		if buyout < 1.1 ^ i then
			item_record.histogram[i] = item_record.histogram[i] + 1
			break
		end
	end

	private.write_record(auction_info.item_key, item_record)
end

function public.price_data(item_key)
	local item_record = private.read_record(item_key)
	return item_record.auction_count, item_record.day_count, private.daily_market_value(item_record.histogram), private.median(item_record.balanced_list)
end

function public.market_value(item_key)
	local auction_count, day_count, daily_market_value, median = public.price_data(item_key)

	if auction_count == 0 then
		return nil
	elseif day_count == 0 then
		return daily_market_value
	else
		return median
	end
end

function private.daily_market_value(histogram)

	local daily_auction_count = 0
	for _, frequency in ipairs(histogram) do
		daily_auction_count = daily_auction_count + frequency
	end

	if daily_auction_count == 0 then
		return 0
	end

	-- average of lowest 25%
	local sum, count = 0, 0
	local limit = daily_auction_count * 0.25
	for i, frequency in ipairs(histogram) do
		local limited_frequency = min(frequency, limit - count)
		sum = sum + 1.1 ^ (i - 1) * 1.05 * limited_frequency
		count = count + limited_frequency
		if count >= limit then
			break
		end
	end
	return sum / limit
end

function private.balanced_list_insert(list, value, max_size)

	local left = 1
	local right = getn(list)
	local middle
	local middle_value
	local insert_position

	while left <= right do
		middle = floor((left + right) / 2)
		middle_value = list[middle]
		if value < middle_value then
			right = middle - 1
		elseif value > middle_value then
			left = middle + 1
		else
			insert_position = middle
			break
		end
	end
	insert_position = insert_position or left

	tinsert(list, insert_position, value)

	if max_size and getn(list) > max_size then
		if insert_position <= floor(max_size / 2) + 1 then
			tremove(list)
		else
			tremove(list, 1)
		end
	end
end

function private.median(list)
	if getn(list) == 0 then
		return
	end
	
	local middle = (getn(list) + 1) / 2
	return (list[floor(middle)] + list[ceil(middle)]) / 2
end

function private.push_data()
	local data = private.load_data()
	local item_data = data.item_data

	for item_key, _ in pairs(item_data) do

		local item_record = private.read_record(item_key)

		if getn(item_record.histogram) ~= 0 then

			local daily_market_value = private.daily_market_value(item_record.histogram)

			private.balanced_list_insert(item_record.balanced_list, daily_market_value, 7)

			item_record.day_count = item_record.day_count + 1
			item_record.histogram = {}

			private.write_record(item_key, item_record)
		end
	end

	data.next_push = time() + private.PUSH_INTERVAL
end

--function private.max_heap(array) -- might use a max heap to keep track of the n smallest values of the day instead of the histogram calculation
--	local self = {}
--
--	local ROOT = 1
--
--	local function parent(i)
--		return floor((i - 2) / 2) + 1
--	end
--
--	local function left_child(i)
--		return 2 * (i - 1) + 2
--	end
--
--	local function right_child(i)
--		return 2 * (i - 1) + 3
--	end
--
--	function self.insert(value)
--		local index = getn(array) + 1
--
--		while index > ROOT and array[index - 1] > 0 do
--			index = index - 1
--		end
--	end
--
--	function self.extract(signature)
--	end
--
--	return self
--end