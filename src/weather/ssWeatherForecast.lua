----------------------------------------------------------------------------------------------------
-- WEATHER FORECAST SCRIPT
----------------------------------------------------------------------------------------------------
-- Purpose:  to create and update the weather forecast
-- Authors:  Rahkiin, reallogger, theSeb
--
-- Copyright (c) Realismus Modding, 2017
----------------------------------------------------------------------------------------------------

ssWeatherForecast = {}
g_seasons.forecast = ssWeatherForecast

ssWeatherForecast.forecast = {} --day of week, low temp, high temp, weather condition
ssWeatherForecast.forecastLength = 8
ssWeatherManager.weather = {}

function ssWeatherForecast:loadMap(name)
    Environment.calculateGroundWetness = Utils.overwrittenFunction(Environment.calculateGroundWetness, ssWeatherManager.calculateSoilWetness)

    if g_currentMission:getIsServer() then
        if table.getn(self.forecast) == 0 or self.forecast[1].day ~= g_seasons.environment:currentDay() then
            self:buildForecast()
        end
        --self.weather = g_currentMission.environment.rains -- should only be done for a fresh savegame, otherwise read from savegame

        self:overwriteRaintable()
        --self:setupStartValues()
    end
end

-- Only run this the very first time or if season length changes
function ssWeatherForecast:buildForecast()
    local startDayNum = g_seasons.environment:currentDay()

    if ssWeatherManager.prevHighTemp == nil then
        ssWeatherManager.prevHighTemp = ssWeatherData.startValues.highAirTemp -- initial assumption high temperature during last day of winter.
    end

    self.forecast = {}
    ssWeatherManager.weather = {}

    for n = 1, self.forecastLength do
        local oneDayForecast = {}
        local oneDayRain = {}
        local ssTmax = {}

        oneDayForecast.day = startDayNum + n - 1 -- To match forecast with actual game
        oneDayForecast.season = g_seasons.environment:seasonAtDay(oneDayForecast.day)

        ssTmax = ssWeatherData.temperatureData[g_seasons.environment:transitionAtDay(oneDayForecast.day)]

        oneDayForecast.highTemp = ssUtil.normDist(ssTmax.mode, 2.5)
        oneDayForecast.lowTemp = ssUtil.normDist(0, 2) + 0.75 * ssTmax.mode - 5

        if n == 1 then
            oneDayRain = self:updateRain(oneDayForecast, 0)
        else
            if oneDayForecast.day == ssWeatherManager.weather[n - 1].endDay then
                oneDayRain = self:updateRain(oneDayForecast, ssWeatherManager.weather[n - 1].endDayTime)
            else
                oneDayRain = self:updateRain(oneDayForecast, 0)
            end
        end

        oneDayForecast.weatherType = oneDayRain.rainTypeId

        table.insert(self.forecast, oneDayForecast)
        table.insert(ssWeatherManager.weather, oneDayRain)
    end

    self:overwriteRaintable()
end

function ssWeatherForecast:updateForecast()
    local dayNum = g_seasons.environment:currentDay() + self.forecastLength - 1
    local oneDayRain = {}

    ssWeatherManager.prevHighTemp = self.forecast[1].highTemp  -- updating prev high temp before updating forecast table

    table.remove(self.forecast, 1)

    local oneDayForecast = {}
    local ssTmax = {}

    oneDayForecast.day = dayNum -- To match forecast with actual game
    oneDayForecast.season = g_seasons.environment:seasonAtDay(dayNum)

    ssTmax = ssWeatherData.temperatureData[g_seasons.environment:transitionAtDay(dayNum)]

    if self.forecast[self.forecastLength - 1].season == oneDayForecast.season then
        --Seasonal average for a day in the current season
        oneDayForecast.Tmaxmean = self.forecast[self.forecastLength - 1].Tmaxmean

    elseif self.forecast[self.forecastLength - 1].season ~= oneDayForecast.season then
        --Seasonal average for a day in the next season
        oneDayForecast.Tmaxmean = ssUtil.triDist(ssTmax)
    end

    oneDayForecast.highTemp = ssUtil.normDist(ssTmax.mode, 2.5)
    oneDayForecast.lowTemp = ssUtil.normDist(0, 2) + 0.75 * ssTmax.mode - 5

    if oneDayForecast.day == ssWeatherManager.weather[self.forecastLength - 1].endDay then
        oneDayRain = self:updateRain(oneDayForecast, ssWeatherManager.weather[self.forecastLength - 1].endDayTime)
    else
        oneDayRain = self:updateRain(oneDayForecast, 0)
    end

    oneDayForecast.weatherType = oneDayRain.rainTypeId

    table.insert(self.forecast, oneDayForecast)
    table.insert(ssWeatherManager.weather, oneDayRain)
    table.remove(ssWeatherManager.weather, 1)

    self:updateHail()
    self:overwriteRaintable()

    g_server:broadcastEvent(ssWeatherManagerDailyEvent:new(oneDayForecast, oneDayRain, ssWeatherManager.prevHighTemp, ssWeatherManager.soilTemp))
end

-- Change rain into snow when it is freezing, and snow into rain if it is too hot
function ssWeatherForecast:switchRainSnow()
    for index, rain in ipairs(g_currentMission.environment.rains) do
        for jndex, fCast in ipairs(self.forecast) do
             if rain.startDay == fCast.day then
                local hour = math.floor(rain.startDayTime / 60 / 60 / 1000)
                local minute = math.floor(rain.startDayTime / 60 / 1000) - hour * 60

                local tempStartRain = ssWeatherManager:diurnalTemp(hour, minute, fCast.lowTemp, fCast.highTemp, fCast.lowTemp)

                if tempStartRain < -1 and rain.rainTypeId == ssWeatherManager.RAINTYPE_RAIN then
                    g_currentMission.environment.rains[index].rainTypeId = ssWeatherManager.RAINTYPE_SNOW
                    self.forecast[jndex].weatherType = ssWeatherManager.RAINTYPE_SNOW

                elseif tempStartRain >= -1 and rain.rainTypeId == ssWeatherManager.RAINTYPE_SNOW then
                    g_currentMission.environment.rains[index].rainTypeId = ssWeatherManager.RAINTYPE_RAIN
                    self.forecast[jndex].weatherType = ssWeatherManager.RAINTYPE_.RAIN
                end
            end
        end
    end
end

function ssWeatherForecast:updateRain(oneDayForecast, endRainTime)
    local rainFactors = ssWeatherData.rainData[g_seasons.environment:seasonAtDay(oneDayForecast.day)]

    local mu = rainFactors.mu
    local sigma = rainFactors.sigma
    local cov = sigma / mu

    rainFactors.beta = 1 / math.sqrt(math.log(1 + cov * cov))
    rainFactors.gamma = mu / math.sqrt(1 + cov * cov)

    local noTime = "false"
    local oneDayRain = {}

    local oneRainEvent = {}

    p = self:_randomRain(oneDayForecast)

    if p < rainFactors.probRain then
        oneRainEvent = self:_rainStartEnd(p, endRainTime, rainFactors, oneDayForecast)

        if oneDayForecast.lowTemp < 1 then
            oneRainEvent.rainTypeId = ssWeatherManager.RAINTYPE_SNOW -- forecast snow if temp < 1
        else
            oneRainEvent.rainTypeId = ssWeatherManager.RAINTYPE_RAIN
        end

    elseif p > rainFactors.probRain and p < rainFactors.probClouds then
        oneRainEvent = self:_rainStartEnd(p, endRainTime, rainFactors, oneDayForecast)
        oneRainEvent.rainTypeId = ssWeatherManager.RAINTYPE_CLOUDY
    elseif oneDayForecast.lowTemp > -1 and oneDayForecast.lowTemp < 4 and endRainTime < 10800000 then
        -- morning fog
        oneRainEvent.startDay = oneDayForecast.day
        oneRainEvent.endDay = oneDayForecast.day
        local dayStart, dayEnd, nightEnd, nightStart = g_seasons.daylight:calculateStartEndOfDay(oneDayForecast.day)

        -- longer fog in winter and autumn
        if oneDayForecast.season == g_seasons.environment.SEASON_WINTER or oneDayForecast.season == g_seasons.environment.SEASON_AUTUMN then
            oneRainEvent.startDayTime = nightEnd * 60 * 60 * 1000
            oneRainEvent.endDayTime = (dayStart + 4) * 60 * 60 * 1000
        else
            oneRainEvent.startDayTime = nightEnd * 60 * 60 * 1000
            oneRainEvent.endDayTime = (dayStart + 1) * 60 * 60 * 1000
        end
        oneRainEvent.duration = oneRainEvent.endDayTime - oneRainEvent.startDayTime
        oneRainEvent.rainTypeId = "fog"
    else
        oneRainEvent.rainTypeId = "sun"
        oneRainEvent.duration = 0
        oneRainEvent.startDayTime = 0
        oneRainEvent.endDayTime = 0
        oneRainEvent.startDay = oneDayForecast.day
        oneRainEvent.endDay = oneDayForecast.day
    end

    oneDayRain = oneRainEvent
    return oneDayRain
end

function ssWeatherForecast:_rainStartEnd(p, endRainTime, rainFactors, oneDayForecast)
    local oneRainEvent = {}

    oneRainEvent.startDay = oneDayForecast.day
    oneRainEvent.duration = math.min(math.max(math.exp(ssUtil.lognormDist(rainFactors.beta, rainFactors.gamma, p)), 2), 24) * 60 * 60 * 1000
    -- rain can start from 01:00 (or 1 hour after last rain ended) to 23.00
    oneRainEvent.startDayTime = math.random(3600 + endRainTime / 1000, 82800) * 1000

    if oneRainEvent.startDayTime + oneRainEvent.duration < 86400000 then
        oneRainEvent.endDay = oneRainEvent.startDay
        oneRainEvent.endDayTime =  oneRainEvent.startDayTime + oneRainEvent.duration
    else
        oneRainEvent.endDay = oneRainEvent.startDay + 1
        oneRainEvent.endDayTime =  oneRainEvent.startDayTime + oneRainEvent.duration - 86400000
    end

    return oneRainEvent
end

function ssWeatherForecast:_randomRain(oneDayForecast)
    ssTmax = ssWeatherData.temperatureData[g_seasons.environment:transitionAtDay(oneDayForecast.day)]

    if oneDayForecast.season == g_seasons.environment.SEASON_WINTER or oneDayForecast.season == g_seasons.environment.SEASON_AUTUMN then
        if oneDayForecast.highTemp > ssTmax.mode then
            p = math.random() ^ 1.5 --increasing probability for precipitation if the temp is high
        else
            p = math.random() ^ 0.75 --decreasing probability for precipitation if the temp is high
        end
    elseif oneDayForecast.season == g_seasons.environment.SEASON_SPRING or oneDayForecast.season == g_seasons.environment.SEASON_SUMMER then
        if oneDayForecast.highTemp < ssTmax.mode then
            p = math.random() ^ 1.5 --increasing probability for precipitation if the temp is high
        else
            p = math.random() ^ 0.75 --decreasing probability for precipitation if the temp is high
        end
    end

    return p
end

-- Overwrite the vanilla rains table using our own forecast
function ssWeatherForecast:overwriteRaintable()
    local env = g_currentMission.environment
    local tmpWeather = {}

    for index = 1, self.forecastLength do
        if ssWeatherManager.weather[index].rainTypeId ~= ssWeatherManager.RAINTYPE_SUN then
            local tmpSingleWeather = deepCopy(ssWeatherManager.weather[index])
            table.insert(tmpWeather, tmpSingleWeather)
        end
    end

    env.numRains = table.getn(tmpWeather)
    env.rains = tmpWeather

    if g_seasons.environment.currentDayOffset ~= nil then
        for index = 1, env.numRains do
            local newStartDay = env.rains[index].startDay - g_seasons.environment.currentDayOffset
            local newEndDay = env.rains[index].endDay - g_seasons.environment.currentDayOffset
            env.rains[index].startDay = newStartDay
            env.rains[index].endDay = newEndDay
        end
    end

    self:switchRainSnow()
end

-- inserting a hail event
function ssWeatherForecast:updateHail(day)
    local rainFactors = ssWeatherData.rainData[self.forecast[1].season]
    local p = math.random()

    if p < rainFactors.probHail and self.forecast[1].weatherType == ssWeatherManager.RAINTYPE_SUN then
        local julianDay = ssUtil.julianDay(g_seasons.environment:currentDay())
        dayStart, dayEnd, _, _ = g_seasons.daylight:calculateStartEndOfDay(julianDay)

        ssWeatherManager.weather[1].rainTypeId = ssWeatherManager.RAINTYPE_HAIL
        ssWeatherManager.weather[1].startDayTime = ssUtil.triDist({["min"] = dayStart, ["mode"] = dayStart + 4, ["max"] = dayEnd - 6}) * 60 * 60 * 1000
        ssWeatherManager.weather[1].duration = ssUtil.triDist({["min"] = 1, ["mode"] = 2, ["max"] = 3}) * 60 * 60 * 1000
        ssWeatherManager.weather[1].endDayTime = ssWeatherManager.weather[1].startDayTime + ssWeatherManager.weather[1].duration
        ssWeatherManager.weather[1].startDay = self.forecast[1].day
        ssWeatherManager.weather[1].endDay = self.forecast[1].day

        g_server:broadcastEvent(ssWeatherManagerHailEvent:new(ssWeatherManager.weather[1]))
    end
end

function ssWeatherForecast:getRainType(hour, day)
    local rainType = ssWeatherManager.RAINTYPE_SUN

    for _, rain in ipairs(ssWeatherManager.weather) do
        local startHour = mathRound(rain.startDayTime / 60 / 60 / 1000, 0)
        local endHour = mathRound((rain.endDayTime) / 60 / 60 / 1000 , 0)
        
        if rain.startDay == day and startHour <= hour and endHour > hour then
            rainType = rain.rainTypeId
        elseif rain.startDay + 1 == day and rain.endDay == day and endHour > hour then
            rainType = rain.rainTypeId
        end
    end
    
    return rainType
end

function ssWeatherForecast:getWeatherType(day, p, temp, avgTemp, windSpeed)
    local season = ssEnvironment:seasonAtDay(day)
    local rainFactors = assWeatherData.rainData[season]

    local pRain = rainFactors.probRain
    local pClouds = rainFactors.probClouds
    local probPartlyCloudy = math.min(pClouds + 0.2, (1 - pClouds) / 2 + pClouds)
    local probCloudy = max(pClouds - 0.1, pClouds - (pClouds - pRain) / 2)
    local probShowers = min(pRain + 0.1, probCloudy - 0.15)
    local probRain = pRain / 2

    local tempLimit = 3
    local wType = ssWeatherManager.WEATHERTYPE_SUN

    if p <= probPartlyCloudy and p > probCloudy then
        wType = ssWeatherManager.WEATHERTYPE_PARTLY_CLOUDY

    elseif p <= probCloudy and p > probShowers and temp >= tempLimit then
        wType = ssWeatherManager.WEATHERTYPE_CLOUDY

    elseif p <= probShowers and p > probRain and temp >= tempLimit then
        wType = ssWeatherManager.WEATHERTYPE_RAIN_SHOWERS

    elseif p <= probRain and temp >= tempLimit then
        wType = ssWeatherManager.WEATHERTYPE_RAIN

    elseif p <= probShowers and temp >= -tempLimit and temp < tempLimit then
        wType = ssWeatherManager.WEATHERTYPE_SLEET

    elseif p <= probShowers and p > probRain and temp < -tempLimit then
        wType = ssWeatherManager.WEATHERTYPE_SNOW_SHOWERS

    elseif p <= probRain and temp < -tempLimit then
        wType = ssWeatherManager.WEATHERTYPE_SNOW

    elseif p > probPartlyCloudy and avgTemp >= -tempLimit and temp < tempLimit and windSpeed < 3.0 then
        if random.random > 0.3 then
            wType = ssWeatherManager.WEATHERTYPE_FOG
        end
    end

    return wType

end

function ssWeatherForecast:calculateAverageTransitionTemp(gt, deterministic)
    local meanMaxTemp = ssWeatherData.temperatureData[gt]
    local avgTemp = meanMaxTemp.mode

    if not deterministic then
        avgTemp = ssUtil.triDist(meanMaxTemp)
    end
    
    return avgTemp
end

function ssWeatherForecast:calculateTemp(meanMaxTemp, deterministic)
    local highTemp = meanMaxTemp
    local lowTemp = 0.75 * meanMaxTemp - 5

    if not deterministic then
        highTemp = ssUtil.normDist(meanMaxTemp, 2.5)
        lowTemp = ssUtil.normDist(0, 2) + 0.75 * meanMaxTemp - 5
    end
    
    return lowTemp, highTemp
end