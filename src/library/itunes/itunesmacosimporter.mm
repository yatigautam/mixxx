#include "library/itunes/itunesmacosimporter.h"

#import <iTunesLibrary/iTunesLibrary.h>

#include <QSqlDatabase>
#include <QSqlQuery>
#include <QString>
#include <memory>

#include "library/itunes/itunesimporter.h"
#include "library/libraryfeature.h"
#include "library/queryutil.h"
#include "library/treeitemmodel.h"

namespace {

void importPlaylist(ITLibPlaylist* playlist, QSqlQuery& queryInsertToPlaylists,
                    QSqlQuery& queryInsertToPlaylistTracks,
                    QSqlDatabase& database,
                    TreeItem& treeItem,
                    bool& cancelImport) {
    // TODO: Support folders and smart playlists

    if (playlist.kind != ITLibPlaylistKindRegular) {
        return;
    }

    long long playlistId = [playlist.persistentID longLongValue];
    QString playlistName = [playlist.name cStringUsingEncoding:NSUTF8StringEncoding];

    queryInsertToPlaylists.bindValue(":id", playlistId);
    queryInsertToPlaylists.bindValue(":name", playlistName);

    // TODO: Handle duplicate playlists by appending id (see xml importer)

    if (!queryInsertToPlaylists.exec()) {
        LOG_FAILED_QUERY(queryInsertToPlaylists);
        return;
    }

    treeItem.appendChild(playlistName);

    int i = 0;
    for (ITLibMediaItem* item in playlist.items) {
        if (cancelImport) {
            return;
        }

        queryInsertToPlaylistTracks.bindValue(":playlist_id", playlistId);
        queryInsertToPlaylistTracks.bindValue(":track_id", [item.persistentID longLongValue]);
        queryInsertToPlaylistTracks.bindValue(":position", i);

        if (!queryInsertToPlaylistTracks.exec()) {
            LOG_FAILED_QUERY(queryInsertToPlaylistTracks);
            return;
        }

        i++;
    }
}

void importMediaItem(ITLibMediaItem* item, QSqlQuery& query, QSqlDatabase& database) {
    query.bindValue(":id", [item.persistentID longLongValue]);
    query.bindValue(":artist", [item.artist.name cStringUsingEncoding:NSUTF8StringEncoding]);
    query.bindValue(":title", [item.title cStringUsingEncoding:NSUTF8StringEncoding]);
    query.bindValue(":album", [item.album.title cStringUsingEncoding:NSUTF8StringEncoding]);
    query.bindValue(
        ":album_artist",
        [item.album.albumArtist cStringUsingEncoding:NSUTF8StringEncoding]);
    query.bindValue(":genre", [item.genre cStringUsingEncoding:NSUTF8StringEncoding]);
    query.bindValue(":grouping", [item.grouping cStringUsingEncoding:NSUTF8StringEncoding]);
    query.bindValue(":year", static_cast<int>(item.year));
    query.bindValue(":duration", static_cast<int>(item.totalTime / 1000));
    query.bindValue(":location", [[item.location path] cStringUsingEncoding:NSUTF8StringEncoding]);
    query.bindValue(":rating", static_cast<int>(item.rating / 20));
    query.bindValue(":comment", [item.comments cStringUsingEncoding:NSUTF8StringEncoding]);
    query.bindValue(":tracknumber", static_cast<int>(item.trackNumber));
    query.bindValue(":bpm", static_cast<int>(item.beatsPerMinute));
    query.bindValue(":bitrate", static_cast<int>(item.bitrate));

    if (!query.exec()) {
        LOG_FAILED_QUERY(query);
        return;
    }
}

std::unique_ptr<TreeItem> importPlaylists(NSArray<ITLibPlaylist*>* playlists,
                                          LibraryFeature* parentFeature,
                                          QSqlDatabase& database,
                                          bool& cancelImport) {
    std::unique_ptr<TreeItem> rootItem = TreeItem::newRoot(parentFeature);

    QSqlQuery queryInsertToPlaylists(database);
    queryInsertToPlaylists.prepare("INSERT INTO itunes_playlists (id, name) VALUES (:id, :name)");

    QSqlQuery queryInsertToPlaylistTracks(database);
    queryInsertToPlaylists.prepare(
        "INSERT INTO itunes_playlist_tracks (playlist_id, track_id, position) "
        "VALUES (:playlist_id, :track_id, :position)");

    qDebug() << "Importing playlists via native iTunesLibrary framework";

    for (ITLibPlaylist* playlist in playlists) {
        if (cancelImport) {
            break;
        }

        importPlaylist(playlist, queryInsertToPlaylists,
                       queryInsertToPlaylistTracks, database, *rootItem, cancelImport);
    }

    return rootItem;
}

void importMediaItems(NSArray<ITLibMediaItem*>* items, QSqlDatabase& database, bool& cancelImport) {
    QSqlQuery query(database);
    query.prepare(
        "INSERT INTO itunes_library (id, artist, title, album, album_artist, "
        "genre, grouping, year, duration, location, rating, comment, "
        "tracknumber, bpm, bitrate) VALUES (:id, :artist, :title, :album, "
        ":album_artist, :genre, :grouping, :year, :duration, :location, "
        ":rating, :comment, :tracknumber, :bpm, :bitrate)");

    qDebug() << "Importing media items via native iTunesLibrary framework";

    for (ITLibMediaItem* item in items) {
        if (cancelImport) {
            break;
        }

        importMediaItem(item, query, database);
    }
}

}  // anonymous namespace

ITunesMacOSImporter::ITunesMacOSImporter(LibraryFeature* parentFeature,
                                         QSqlDatabase& database,
                                         bool& cancelImport)
    : m_parentFeature(parentFeature),
      m_database(database),
      m_cancelImport(cancelImport) {
}

ITunesImport ITunesMacOSImporter::importLibrary() {
    ITunesImport iTunesImport;
    iTunesImport.isMusicFolderLocatedAfterTracks = false;

    NSError* error = nil;
    ITLibrary* library = [[ITLibrary alloc] initWithAPIVersion:@"1.0" error:&error];

    if (library) {
        iTunesImport.playlistRoot = importPlaylists(
            library.allPlaylists, m_parentFeature, m_database, m_cancelImport);
        importMediaItems(library.allMediaItems, m_database, m_cancelImport);
    }

    return iTunesImport;
}
