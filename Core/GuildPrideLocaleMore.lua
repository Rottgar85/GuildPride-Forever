-- GuildPride: weitere Sprachen (Französisch, Spanisch, Russisch)
-- Schlüssel ist wie überall der deutsche Text. Was hier fehlt, erscheint auf Englisch.
-- Bisher übersetzt: Menü, häufige Knöpfe, Werkzeuge und die Frage zum Fehler-Senden.
-- Weitere Texte: python .github/export-locale.py frFR zeigt, was noch fehlt. Muttersprachler
-- sollten die Texte gegenlesen. Platzhalter (%s, %d) müssen gleich bleiben (tests/gilde2.lua prüft es).
local ADDON, ns = ...

local ASK = "In GuildPride ist ein Fehler aufgetreten. Dürfen solche Fehler automatisch im Spiel an den Entwickler von GuildPride gehen? Dann werden sie schneller behoben.\n\nGesendet werden nur Fehlertext (kann selten einen Spielernamen enthalten), Stelle im Code, Versionen von GuildPride und WoW, die Spielsprache und die Umstände (Kampf, Instanzart, offene GuildPride-Fenster). Deinen Charakternamen speichert er nicht, nur einen daraus berechneten Zählcode.\n\nDu kannst das jederzeit ändern: Einstellungen › Teilen."

local M = {}
ns.MORE_LOCALES = M

M.frFR = {
    ["Übersicht"] = "Aperçu", ["Meilensteine"] = "Étapes", ["Ziele"] = "Objectifs", ["Planen"] = "Planifier",
    ["Wünsche"] = "Souhaits", ["Umfragen"] = "Sondages", ["Offene Dungeons"] = "Donjons à faire", ["Werkzeuge"] = "Outils",
    ["Handwerk"] = "Artisanat", ["Gruppensuche"] = "Recherche de groupe", ["Gilde & Chat"] = "Guilde et discussion",
    ["Gildeninfo"] = "Infos de guilde", ["Verwaltung"] = "Gestion", ["Aktivität"] = "Activité", ["Einstellungen"] = "Réglages",
    ["Speichern"] = "Enregistrer", ["Löschen"] = "Supprimer", ["Neu"] = "Nouveau", ["Nein"] = "Non", ["Ja, immer"] = "Oui, toujours",
    ["Weiter"] = "Suivant", ["Zurück"] = "Retour", ["Fertig"] = "Terminé", ["Aktualisieren"] = "Actualiser",
    ["Menge"] = "Quantité", ["Anlegen"] = "Créer", ["Allgemein"] = "Général", ["Hinweise"] = "Notifications", ["Teilen"] = "Partage",
    ["Auktionshaus"] = "Hôtel des ventes", ["Reisen"] = "Voyages", ["Gilde"] = "Guilde", ["Twinks"] = "Rerolls",
    ["Nachricht des Tages"] = "Message du jour", ["Diese Woche"] = "Cette semaine", ["Letzte Meilensteine"] = "Dernières étapes",
    ["offline"] = "hors ligne", ["Neue Mitglieder"] = "Nouveaux membres", ["Abgänge"] = "Départs",
    ["Raid-Bereitschaft"] = "Préparation du raid", ["Quests der Gilde"] = "Quêtes de la guilde", ["Boss-Notizen"] = "Notes de boss",
    ["Materialliste der Gilde"] = "Matériaux de la guilde", ["Event-Auswertung"] = "Statistiques d'événements",
    ["Gruppe fragen"] = "Demander au groupe", ["bereit"] = "prêt", ["keine Tränke"] = "pas de potions",
    ["%d Teile kaputt"] = "%d pièces cassées", ["%d Tränke"] = "%d potions", ["%d Elixiere"] = "%d élixirs",
    ["%d in deiner Zone"] = "%d dans votre zone", ["Ich steuere bei"] = "Je contribue",
    ["Fehler automatisch senden?"] = "Envoyer les erreurs automatiquement ?",
    [ASK] = "Une erreur s'est produite dans GuildPride. Ces erreurs peuvent-elles être envoyées automatiquement, en jeu, au développeur de GuildPride ? Elles seront corrigées plus vite.\n\nSont envoyés uniquement : le texte de l'erreur (peut rarement contenir un nom de joueur), l'endroit dans le code, les versions de GuildPride et de WoW, la langue du jeu et les circonstances (combat, type d'instance, fenêtres GuildPride ouvertes). Le développeur n'enregistre pas le nom de votre personnage, seulement un code de comptage calculé à partir de celui-ci.\n\nVous pouvez changer cela à tout moment : Réglages › Partage.",
}

M.esES = {
    ["Übersicht"] = "Resumen", ["Meilensteine"] = "Hitos", ["Ziele"] = "Objetivos", ["Planen"] = "Planificar",
    ["Wünsche"] = "Deseos", ["Umfragen"] = "Encuestas", ["Offene Dungeons"] = "Mazmorras pendientes", ["Werkzeuge"] = "Herramientas",
    ["Handwerk"] = "Artesanía", ["Gruppensuche"] = "Buscar grupo", ["Gilde & Chat"] = "Hermandad y chat",
    ["Gildeninfo"] = "Información", ["Verwaltung"] = "Gestión", ["Aktivität"] = "Actividad", ["Einstellungen"] = "Ajustes",
    ["Speichern"] = "Guardar", ["Löschen"] = "Borrar", ["Neu"] = "Nuevo", ["Nein"] = "No", ["Ja, immer"] = "Sí, siempre",
    ["Weiter"] = "Siguiente", ["Zurück"] = "Atrás", ["Fertig"] = "Listo", ["Aktualisieren"] = "Actualizar",
    ["Menge"] = "Cantidad", ["Anlegen"] = "Crear", ["Allgemein"] = "General", ["Hinweise"] = "Avisos", ["Teilen"] = "Compartir",
    ["Auktionshaus"] = "Casa de subastas", ["Reisen"] = "Viajes", ["Gilde"] = "Hermandad", ["Twinks"] = "Alters",
    ["Nachricht des Tages"] = "Mensaje del día", ["Diese Woche"] = "Esta semana", ["Letzte Meilensteine"] = "Últimos hitos",
    ["offline"] = "desconectado", ["Neue Mitglieder"] = "Miembros nuevos", ["Abgänge"] = "Bajas",
    ["Raid-Bereitschaft"] = "Preparación de banda", ["Quests der Gilde"] = "Misiones de la hermandad", ["Boss-Notizen"] = "Notas de jefes",
    ["Materialliste der Gilde"] = "Materiales de la hermandad", ["Event-Auswertung"] = "Estadísticas de eventos",
    ["Gruppe fragen"] = "Preguntar al grupo", ["bereit"] = "listo", ["keine Tränke"] = "sin pociones",
    ["%d Teile kaputt"] = "%d piezas rotas", ["%d Tränke"] = "%d pociones", ["%d Elixiere"] = "%d elixires",
    ["%d in deiner Zone"] = "%d en tu zona", ["Ich steuere bei"] = "Yo aporto",
    ["Fehler automatisch senden?"] = "¿Enviar errores automáticamente?",
    [ASK] = "Se ha producido un error en GuildPride. ¿Pueden enviarse estos errores automáticamente, dentro del juego, al desarrollador de GuildPride? Así se corrigen antes.\n\nSolo se envían el texto del error (rara vez puede contener el nombre de un jugador), el lugar en el código, las versiones de GuildPride y WoW, el idioma del juego y las circunstancias (combate, tipo de estancia, ventanas de GuildPride abiertas). El desarrollador no guarda el nombre de tu personaje, solo un código de recuento calculado a partir de él.\n\nPuedes cambiarlo en cualquier momento: Ajustes › Compartir.",
}
M.esMX = M.esES

M.ruRU = {
    ["Übersicht"] = "Обзор", ["Meilensteine"] = "Достижения гильдии", ["Ziele"] = "Цели", ["Planen"] = "Планы",
    ["Wünsche"] = "Пожелания", ["Umfragen"] = "Опросы", ["Offene Dungeons"] = "Нужные подземелья", ["Werkzeuge"] = "Инструменты",
    ["Handwerk"] = "Ремёсла", ["Gruppensuche"] = "Поиск группы", ["Gilde & Chat"] = "Гильдия и чат",
    ["Gildeninfo"] = "О гильдии", ["Verwaltung"] = "Управление", ["Aktivität"] = "Активность", ["Einstellungen"] = "Настройки",
    ["Speichern"] = "Сохранить", ["Löschen"] = "Удалить", ["Neu"] = "Новый", ["Nein"] = "Нет", ["Ja, immer"] = "Да, всегда",
    ["Weiter"] = "Далее", ["Zurück"] = "Назад", ["Fertig"] = "Готово", ["Aktualisieren"] = "Обновить",
    ["Menge"] = "Количество", ["Anlegen"] = "Создать", ["Allgemein"] = "Общие", ["Hinweise"] = "Уведомления", ["Teilen"] = "Обмен данными",
    ["Auktionshaus"] = "Аукцион", ["Reisen"] = "Путешествия", ["Gilde"] = "Гильдия", ["Twinks"] = "Альты",
    ["Nachricht des Tages"] = "Сообщение дня", ["Diese Woche"] = "На этой неделе", ["Letzte Meilensteine"] = "Последние события",
    ["offline"] = "не в сети", ["Neue Mitglieder"] = "Новые участники", ["Abgänge"] = "Ушедшие",
    ["Raid-Bereitschaft"] = "Готовность рейда", ["Quests der Gilde"] = "Задания гильдии", ["Boss-Notizen"] = "Заметки о боссах",
    ["Materialliste der Gilde"] = "Материалы гильдии", ["Event-Auswertung"] = "Статистика событий",
    ["Gruppe fragen"] = "Опросить группу", ["bereit"] = "готов", ["keine Tränke"] = "нет зелий",
    ["%d Teile kaputt"] = "сломано предметов: %d", ["%d Tränke"] = "зелий: %d", ["%d Elixiere"] = "эликсиров: %d",
    ["%d in deiner Zone"] = "в вашей зоне: %d", ["Ich steuere bei"] = "Я внесу",
    ["Fehler automatisch senden?"] = "Отправлять ошибки автоматически?",
    [ASK] = "В GuildPride произошла ошибка. Можно ли автоматически, внутри игры, отправлять такие ошибки разработчику GuildPride? Так их исправят быстрее.\n\nОтправляются только текст ошибки (изредка может содержать имя игрока), место в коде, версии GuildPride и WoW, язык игры и обстоятельства (бой, тип подземелья, открытые окна GuildPride). Имя вашего персонажа разработчик не сохраняет, только вычисленный из него код для подсчёта.\n\nЭто можно изменить в любой момент: Настройки › Обмен данными.",
}
