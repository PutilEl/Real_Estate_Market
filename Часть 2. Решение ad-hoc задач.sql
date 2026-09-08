/* Проект первого модуля: анализ данных для агентства недвижимости
 * Часть 2. Решаем ad hoc задачи
 *
 * Автор: Путилина Елизавета
 * Дата: 30.03.2026
*/

-- Задача 1: Время активности объявлений
/* Результат запроса должен ответить на такие вопросы:
   1. Какие категории объявлений являются самыми распространёнными в Санкт-Петербурге и 
   городах Ленинградской области?
   2.Какие характеристики недвижимости, включая площадь недвижимости, среднюю стоимость 
   квадратного метра, количество комнат и балконов и другие параметры, влияют на время 
   активности объявлений? Как эти зависимости варьируют между регионами?
   3.Есть ли различия между недвижимостью Санкт-Петербурга и Ленинградской области по полученным результатам?
*/
-- СТЕ для определения аномальных значений (выбросы) по значению перцентилей
WITH limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats     
),
-- СТЕ для поиска id объявлений, которые не содержат выбросы
filtered_id AS(
    SELECT id
    FROM real_estate.flats  
    WHERE 
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
            AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
),
-- СТЕ для определения наиболее коротких или длинных сроков активности объявлений в период 2015-2018 годов
active_days AS (
	SELECT
		a.id,
		-- Присвоим категорию Санкт-Петербург, если город объявления соответствует идентификатору Санкт-Петербурга
		CASE
			WHEN c.city = 'Санкт-Петербург' THEN 'Санкт-Петербург'
			ELSE 'ЛенОбл'
		END AS region,
		-- Присвоим категорию по количеству дней активности объявлений
		CASE
			WHEN a.days_exposition <= 30 THEN 'до месяца'
			WHEN a.days_exposition BETWEEN 31 AND 90 THEN 'до трёх месяцев'
			WHEN a.days_exposition BETWEEN 91 AND 180 THEN 'до полугода'
			WHEN a.days_exposition >= 180 THEN 'более полугода'
			ELSE 'non category'
		END AS active_periods,
		f.total_area, -- Общая площадь квартиры, в кв. метрах
		f.ceiling_height, -- Высота потолка
        f.rooms, -- Количество комнат
        f.is_apartment, -- Указатель, является ли квартира апартаментами
        f.open_plan, -- Указатель, имеется ли в квартире открытая планировка
        f.balcony, -- Количество балконов
        f.floor, -- Этаж квартиры
        f.airports_nearest, -- Расстояние до ближайшего аэропорта, м
        f.parks_around3000, -- Число парков в радиусе трёх километров
        f.ponds_around3000, -- Число водоёмов в радиусе трёх километров
        a.last_price / NULLIF(f.total_area, 0) AS price_per_kvm -- Стоимость одного кв. метра
	FROM real_estate.advertisement a
    LEFT JOIN real_estate.flats f USING(id)
    LEFT JOIN real_estate.city c USING(city_id)
    LEFT JOIN real_estate.type AS t USING(type_id)
    WHERE a.id IN (SELECT id FROM filtered_id)
			AND a.first_day_exposition >= '2015-01-01'
      		AND a.first_day_exposition <= '2018-12-31'
      		AND t.type = 'город'
)
-- Основной запрос
SELECT 
	region, -- Регион
	active_periods, -- Активные периоды
	COUNT(id) AS abs_count_id, -- Количество объявлений
	-- Доля активных объявлений
	ROUND((COUNT(id)::NUMERIC / SUM(COUNT(id)) OVER (PARTITION BY region)) * 100, 2) AS count_id_percent,
	-- Доля апартаментов
	ROUND((SUM(is_apartment)::NUMERIC / SUM(COUNT(id)) OVER (PARTITION BY region)) * 100, 2) AS count_is_apartment_percent,
	-- Доля открытой планировки
	ROUND((SUM(open_plan)::NUMERIC / SUM(COUNT(id)) OVER (PARTITION BY region)) * 100, 2) AS count_open_plan_percent,
	-- Средняя цена за кв.м.
	ROUND(AVG(price_per_kvm)::NUMERIC, 2) AS avg_price_per_kvm,
	-- Средняя общая площадь квартиры
	ROUND(AVG(total_area)::NUMERIC, 2) AS avg_total_area,
	-- Средняя высота потолка
	ROUND(AVG(ceiling_height)::NUMERIC, 2) AS avg_ceiling_height,
	-- Среднее расстояние до ближайшего аэропорта
	ROUND(AVG(airports_nearest)::NUMERIC, 2) AS avg_airports_nearest,
	-- Медиана по количеству комнат
	PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY rooms) AS median_rooms,
	-- Медиана по количеству балконов
    PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY balcony) AS median_balcony,
    -- Медиана по этажу квартиры
    PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY floor) AS median_floor,
    -- Медиана числа парков в радиусе трех километров
    PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY parks_around3000) AS median_parks_around3000,
    -- Медиана числа водоемов в радиусе трех километров
    PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY ponds_around3000) AS median_ponds_around3000
FROM active_days
GROUP BY region, active_periods
ORDER BY 
		region DESC, 
		CASE active_periods
			WHEN 'до месяца' THEN 1
			WHEN 'до трёх месяцев' THEN 2
			WHEN 'до полугода' THEN 3
			WHEN 'более полугода' THEN 4
			ELSE 5
		END;

-- Задача 2: Сезонность объявлений
/*  Результат запроса должен ответить на такие вопросы:
    1. В какие месяцы наблюдается наибольшая активность в публикации объявлений о продаже недвижимости? 
    А в какие — по снятию? Это показывает динамику активности покупателей.
    2.Совпадают ли периоды активной публикации объявлений и периоды, когда происходит повышенная продажа 
    недвижимости (по месяцам снятия объявлений)?
    3.Как сезонные колебания влияют на среднюю стоимость квадратного метра и среднюю площадь квартир? 
    Что можно сказать о зависимости этих параметров от месяца?
*/
-- СТЕ для определения аномальных значений (выбросы) по значению перцентилей
WITH limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats     
),
-- СТЕ для поиска id объявлений в городах, которые не содержат выбросы
filtered_id AS(
    SELECT id
    FROM real_estate.flats AS f
    LEFT JOIN real_estate.type AS t USING(type_id)
    WHERE 
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
            AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
		AND t.type = 'город'
),
-- СТЕ для выделения месяца публикации и месяца снятия объявления с продажи в период 2015–2018 годов
months_information AS (
	SELECT 	
			a.id,
			EXTRACT(MONTH FROM a.first_day_exposition) AS month_publication,
			EXTRACT(MONTH FROM a.first_day_exposition + INTERVAL '1 DAY' * a.days_exposition) AS month_remove,
			a.last_price / f.total_area AS price_kvm,
			f.total_area
	FROM real_estate.advertisement AS a
	LEFT JOIN real_estate.flats AS f USING(id)
	WHERE a.id IN (SELECT id FROM filtered_id)
			AND a.first_day_exposition >= '2015-01-01'
      		AND a.first_day_exposition <= '2018-12-31'
),
-- СТЕ для определения статистики по активным объявлениям
activity_publication AS (
	SELECT 	
			month_publication,
			COUNT(id) AS publication_count,
			ROUND(AVG(price_kvm)::NUMERIC, 2) AS avg_price_kvm_active,
			ROUND(AVG(total_area)::NUMERIC, 2) AS avg_total_area_active
	FROM months_information
	GROUP BY month_publication
),
-- СТЕ для определения статистики по снятым объявлениям
remove_publication AS (
	SELECT 
			month_remove,
			COUNT(id) AS remove_count,
			ROUND(AVG(price_kvm)::NUMERIC, 2) AS avg_price_kvm_removed,
			ROUND(AVG(total_area)::NUMERIC, 2) AS avg_total_area_removed
			FROM months_information
			GROUP BY month_remove
)
-- Основной запрос
SELECT 
		ap.month_publication AS month, -- Месяц
		ap.publication_count, -- Количество активных объявлений
		-- Доля активных объявлений
		ROUND(ap.publication_count::NUMERIC / (SELECT COUNT(id) FROM months_information) * 100, 2) AS publication_percent,
		rp.remove_count, -- Количество снятых объявлений
		-- Доля снятых объявлений
		ROUND(rp.remove_count::NUMERIC / (SELECT COUNT(id) FROM months_information) * 100, 2) AS remove_percent,
		-- Средняя стоимость за кв.м в активных объявлениях
		ap.avg_price_kvm_active,
		-- Средняя общая площадь квартиры в активных объявлениях
		ap.avg_total_area_active,
		-- Средняя стоимость за кв.м в снятых объявлениях
		rp.avg_price_kvm_removed,
		-- Средняя общая площадь квартиры в снятых объявлениях
		rp.avg_total_area_removed
FROM activity_publication AS ap
LEFT JOIN remove_publication rp ON ap.month_publication = rp.month_remove
ORDER BY ap.publication_count;
