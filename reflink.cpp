// Copyright (c) Facebook, Inc. and its affiliates.
//
// This source code is licensed under the MIT license found in the
// LICENSE file in the root directory of this source tree.

#include <libdnf5/base/base.hpp>
#include <libdnf5/base/transaction.hpp>
#include <libdnf5/base/transaction_package.hpp>
#include <libdnf5/conf/config_parser.hpp>
#include <libdnf5/plugin/iplugin.hpp>
#include <libdnf5/rpm/checksum.hpp>
#include <libdnf5/transaction/transaction_item_action.hpp>

#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <set>
#include <string>
#include <sys/vfs.h>

using namespace libdnf5;

namespace {

constexpr const char * PLUGIN_NAME = "reflink";
constexpr PluginAPIVersion REQUIRED_PLUGIN_API_VERSION{.major = 2, .minor = 1};
constexpr plugin::Version PLUGIN_VERSION{0, 1, 0};

constexpr const char * TRANSCODER_PATHS[]{
    "/usr/libexec/rpm/rpm2extents",
    "/usr/lib/rpm/rpm2extents",
    "/usr/bin/rpm2extents",
};

// Filesystem magic numbers for reflink-capable filesystems
constexpr unsigned long XFS_SUPER_MAGIC = 0x58465342;
constexpr unsigned long BTRFS_SUPER_MAGIC = 0x9123683E;

constexpr const char * attrs[]{"author.name", "author.email", "description", nullptr};
constexpr const char * attrs_value[]{"Matteo Croce", "teknoraver@meta.com",
    "Enable CoW/reflink transcoding for RPM packages"};

static const char * find_transcoder() {
    for (const auto & path : TRANSCODER_PATHS)
        if (std::filesystem::exists(path))
            return path;
    return nullptr;
}

static bool is_reflink_fs(const std::string & path) {
    struct statfs buf;
    if (statfs(path.c_str(), &buf) != 0)
        return false;
    return buf.f_type == XFS_SUPER_MAGIC || buf.f_type == BTRFS_SUPER_MAGIC;
}

static const char * checksum_type_to_str(rpm::Checksum::Type type) {
    switch (type) {
        case rpm::Checksum::Type::MD5:
            return "MD5";
        case rpm::Checksum::Type::SHA1:
            return "SHA1";
        case rpm::Checksum::Type::SHA224:
            return "SHA224";
        case rpm::Checksum::Type::SHA256:
            return "SHA256";
        case rpm::Checksum::Type::SHA384:
            return "SHA384";
        case rpm::Checksum::Type::SHA512:
            return "SHA512";
        default:
            return nullptr;
    }
}

class ReflinkPlugin : public plugin::IPlugin2_1 {
public:
    ReflinkPlugin(plugin::IPluginData & data, ConfigParser & parser)
        : IPlugin2_1(data), parser(parser) {}

    PluginAPIVersion get_api_version() const noexcept override { return REQUIRED_PLUGIN_API_VERSION; }
    const char * get_name() const noexcept override { return PLUGIN_NAME; }
    plugin::Version get_version() const noexcept override { return PLUGIN_VERSION; }
    const char * const * get_attributes() const noexcept override { return attrs; }

    const char * get_attribute(const char * name) const noexcept override {
        for (size_t i = 0; attrs[i]; ++i)
            if (std::strcmp(attrs[i], name) == 0)
                return attrs_value[i];
        return nullptr;
    }

    void post_base_setup() override {
        // deny list
        if (parser.has_section("main") && parser.has_option("main", "denylist")) {
            const auto & denylist = parser.get_value("main", "denylist");
            if (!denylist.empty())
                setenv("LIBREPO_TRANSCODE_RPMS_DENYLIST", denylist.c_str(), 1);
        }
    }

    void goal_resolved(const libdnf5::base::Transaction & transaction) override {
        if (get_base().get_config().get_downloadonly_option().get_value())
            return;

        // Skip transcoding if the cache filesystem doesn't support reflinks
        if (!is_reflink_fs(get_base().get_config().get_cachedir_option().get_value()))
            return;

        const auto * transcoder = find_transcoder();
        if (!transcoder)
            return;

        // Detect checksum algorithms from the transaction's install set
        std::set<std::string> algos;
        for (const auto & tpkg : transaction.get_transaction_packages()) {
            if (!transaction::transaction_item_action_is_inbound(tpkg.get_action()))
                continue;
            const auto * algo = checksum_type_to_str(tpkg.get_package().get_checksum().get_type());
            if (algo)
                algos.insert(algo);
        }

        if (algos.empty())
            return;

        std::string value = transcoder;
        for (const auto & algo : algos)
            value += " " + algo;
        setenv("LIBREPO_TRANSCODE_RPMS", value.c_str(), 1);
    }

private:
    ConfigParser & parser;
};

std::exception_ptr last_exception;

}  // namespace

PluginAPIVersion libdnf_plugin_get_api_version(void) {
    return REQUIRED_PLUGIN_API_VERSION;
}

const char * libdnf_plugin_get_name(void) {
    return PLUGIN_NAME;
}

plugin::Version libdnf_plugin_get_version(void) {
    return PLUGIN_VERSION;
}

plugin::IPlugin * libdnf_plugin_new_instance(
    [[maybe_unused]] LibraryVersion library_version,
    plugin::IPluginData & data,
    ConfigParser & parser) try {
    return new ReflinkPlugin(data, parser);
} catch (...) {
    last_exception = std::current_exception();
    return nullptr;
}

void libdnf_plugin_delete_instance(plugin::IPlugin * plugin_object) {
    delete plugin_object;
}

std::exception_ptr * libdnf_plugin_get_last_exception(void) {
    return &last_exception;
}
